import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/island_banner.dart';
import 'package:vibration/vibration.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/nearby_store.dart';
import '../services/socket_service.dart';
import '../theme/brutal_theme.dart';
import 'profile_screen.dart';

/// Sigma Nearby — AirDrop/NameDrop-style profile exchange.
///
/// Both people open this screen; each phone gets a short-lived random token
/// from the server and advertises it via Nearby Connections (BLE + Wi-Fi)
/// while simultaneously discovering. When the other phone's token is seen we
/// call the server, which verifies BOTH sides have the screen open, makes the
/// follow mutual, gives both +5 Aura and pushes the result to the passive
/// phone over the socket. No user data ever travels over the air — only the
/// rotating token.
class SigmaNearbyScreen extends StatefulWidget {
  final Map user;
  const SigmaNearbyScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<SigmaNearbyScreen> createState() => _SigmaNearbyScreenState();
}

enum _Phase { boot, perms, searching, choose, connecting, connected, error }

class _SigmaNearbyScreenState extends State<SigmaNearbyScreen>
    with TickerProviderStateMixin {
  static const _serviceId = 'com.sigmacta.nearby';
  static const _strategy = Strategy.P2P_CLUSTER;

  _Phase _phase = _Phase.boot;
  String _error = '';

  String? _token;
  Timer? _rotateTimer;
  Timer? _autoConnect;
  Timer? _lostBanner;
  bool _lostVisible = false;

  /// Discovered peers: token → public profile (from /nearby/peek).
  final Map<String, Map> _peers = {};

  /// endpointId → token, so onEndpointLost can clean up.
  final Map<String, String> _endpointToken = {};

  Map? _partner; // the profile we're connecting / connected with

  /// Peer currently announced by the top island banner, if any.
  Map? _islandPeer;

  // ── animation ──
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))
        ..repeat();
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();
  late final AnimationController _join = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _burst = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));

  // ── feedback (sound + vibration) ──
  final AudioPlayer _sfx = AudioPlayer();

  /// Real vibration — HapticFeedback.* is silently ignored on many Androids
  /// unless the system "touch vibration" toggle is on.
  Future<void> _vibe({List<int>? pattern, int duration = 80}) async {
    try {
      final has = await Vibration.hasVibrator();
      if (has != true) return;
      if (pattern != null) {
        Vibration.vibrate(pattern: pattern);
      } else {
        Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  void _sound(String name) {
    try {
      _sfx.play(AssetSource('sounds/$name.wav'), volume: 0.85);
    } catch (_) {}
  }

  bool get _excited =>
      _phase == _Phase.choose ||
      _phase == _Phase.connecting ||
      _phase == _Phase.connected ||
      _peers.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    _autoConnect?.cancel();
    _lostBanner?.cancel();
    _spin.dispose();
    _pulse.dispose();
    _join.dispose();
    _burst.dispose();
    _sfx.dispose();
    SocketService().onNearbyConnected = null;
    try {
      Nearby().stopAllEndpoints();
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
    } catch (_) {}
    ApiService.nearbyStop();
    super.dispose();
  }

  // ─── lifecycle ─────────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (!Platform.isAndroid) {
      setState(() {
        _phase = _Phase.error;
        _error = context.t('nearbyAndroidOnly');
      });
      return;
    }
    if (!await _ensurePermissions()) {
      if (mounted) setState(() => _phase = _Phase.perms);
      return;
    }

    _token = await ApiService.nearbyStart();
    if (_token == null || _token!.isEmpty) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = context.t('nearbyStartFailed');
        });
      }
      return;
    }

    // The passive phone learns about a completed exchange over the socket.
    final uid = (widget.user['id'] ?? '').toString();
    SocketService().connect(uid);
    SocketService().onNearbyConnected = (data) {
      final them = data['user'];
      if (them is Map && _phase != _Phase.connected && mounted) {
        _onPaired(Map.from(them));
      }
    };

    try {
      await Nearby().startAdvertising(
        _token!,
        _strategy,
        serviceId: _serviceId,
        onConnectionInitiated: (id, info) => Nearby().rejectConnection(id),
        onConnectionResult: (id, status) {},
        onDisconnected: (id) {},
      );
      await Nearby().startDiscovery(
        _token!,
        _strategy,
        serviceId: _serviceId,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = _friendlyError(e);
        });
      }
      return;
    }

    HapticFeedback.selectionClick();
    if (mounted) setState(() => _phase = _Phase.searching);

    // Rotate the advertised token before it expires (server TTL = 2 min).
    _rotateTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      final t = await ApiService.nearbyStart();
      if (t == null || !mounted) return;
      _token = t;
      try {
        await Nearby().stopAdvertising();
        await Nearby().startAdvertising(
          _token!,
          _strategy,
          serviceId: _serviceId,
          onConnectionInitiated: (id, info) => Nearby().rejectConnection(id),
          onConnectionResult: (id, status) {},
          onDisconnected: (id) {},
        );
      } catch (_) {}
    });
  }

  /// True when the location TOGGLE is off (distinct from the permission being
  /// denied). Nearby Connections needs the service itself running for BLE
  /// scanning, and fails with a bare MISSING_PERMISSION error when it isn't —
  /// which is unreadable unless we check for it up front.
  bool _locationServiceOff = false;

  /// Set when the OS will no longer show a permission prompt, so the UI has to
  /// send the user to app settings instead of retrying.
  bool _permsPermanentlyDenied = false;

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
    // On Android < 12 the bluetooth* runtime permissions don't exist and are
    // reported granted; nearbyWifiDevices only exists on 13+.
    final loc = statuses[Permission.location];
    // `limited` is the "Approximate location only" grant — coarse without
    // fine. Nearby's BLE path only needs coarse, so that's good enough and
    // must not be treated as a refusal.
    final locOk = (loc?.isGranted ?? false) || (loc?.isLimited ?? false);
    final ok = locOk &&
        (statuses[Permission.bluetoothScan]?.isGranted ?? true) &&
        (statuses[Permission.bluetoothAdvertise]?.isGranted ?? true) &&
        (statuses[Permission.bluetoothConnect]?.isGranted ?? true);

    _permsPermanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);

    if (ok) {
      // Granted, but the device-wide location switch can still be off.
      try {
        _locationServiceOff =
            !(await Permission.location.serviceStatus.isEnabled);
      } catch (_) {
        _locationServiceOff = false;
      }
      if (_locationServiceOff) return false;
    }
    return ok;
  }

  /// Turns a raw plugin exception into something a person can act on. Nearby
  /// surfaces failures as `PlatformException(Failure, 8034: MISSING_PERMISSION_…)`,
  /// and printing that verbatim is what made this screen look broken.
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('MISSING_PERMISSION')) return context.t('nearbyErrPerms');
    if (s.contains('BLUETOOTH') || s.contains('bluetooth')) {
      return context.t('nearbyErrBluetooth');
    }
    if (s.contains('8007') || s.contains('ALREADY')) {
      return context.t('nearbyErrBusy');
    }
    return context.t('nearbyErrGeneric');
  }

  // ─── discovery ─────────────────────────────────────────────────────────────

  void _onEndpointFound(String id, String name, String serviceId) async {
    final token = name.trim();
    if (token.isEmpty || token == _token) return;
    _endpointToken[id] = token;
    if (_peers.containsKey(token)) return;
    if (_phase == _Phase.connecting || _phase == _Phase.connected) return;

    final profile = await ApiService.nearbyPeek(token);
    if (!mounted || profile == null) return;
    // The peek fails for strangers whose session already expired — ignore.
    if (_peers.containsKey(token)) return;

    _peers[token] = profile;
    _vibe(duration: 90); // short buzz — user found
    _sound('nearby_found');

    setState(() {
      _lostVisible = false;
      if (_peers.length == 1) {
        _partner = profile;
        // Announce, and let the user confirm — no silent auto-connect. Pairing
        // makes both people follow each other, which is too consequential to
        // happen without a tap.
        _islandPeer = profile;
      } else {
        _phase = _Phase.choose; // several people around — let the user pick
        _islandPeer = null;
        _autoConnect?.cancel();
      }
    });
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    final token = _endpointToken.remove(id);
    if (token == null) return;
    if (_phase == _Phase.connecting || _phase == _Phase.connected) return;
    setState(() {
      _peers.remove(token);
      // The island must not keep offering someone who has walked away.
      if (_islandPeer != null &&
          !_peers.values.any((p) => p['id'] == _islandPeer!['id'])) {
        _islandPeer = null;
      }
      if (_peers.isEmpty) {
        _partner = null;
        _phase = _Phase.searching;
        _lostVisible = true;
      } else if (_peers.length == 1) {
        _phase = _Phase.searching;
        _partner = _peers.values.first;
        _islandPeer = _peers.values.first;
      }
    });
    _lostBanner?.cancel();
    _lostBanner = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _lostVisible = false);
    });
  }

  // ─── pairing ───────────────────────────────────────────────────────────────

  Future<void> _connect(String token) async {
    final profile = _peers[token];
    if (profile == null) return;
    setState(() {
      _partner = profile;
      _phase = _Phase.connecting;
      _islandPeer = null;
    });
    _join.forward(from: 0);
    final them = await ApiService.nearbyConnect(token);
    if (!mounted) return;
    if (them == null) {
      // Their session expired between discovery and tap — back to searching.
      setState(() {
        _peers.remove(token);
        _partner = null;
        _phase = _Phase.searching;
        _lostVisible = true;
      });
      return;
    }
    _onPaired(them);
  }

  void _onPaired(Map them) {
    _autoConnect?.cancel();
    setState(() {
      _partner = them;
      _phase = _Phase.connected;
    });
    if (_join.value == 0) _join.forward(from: 0);
    _burst.forward(from: 0);
    NearbyStore.add(them); // "Recent connections" on the Discover screen
    _vibe(pattern: [0, 90, 70, 90]); // double buzz — connection established
    _sound('nearby_success');
    // soft long buzz when the mutual follow lands
    Future.delayed(
        const Duration(milliseconds: 1000), () => _vibe(duration: 180));
    // Let the success animation breathe, then open their profile.
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            user: widget.user,
            targetUserId: (_partner!['id'] ?? '').toString(),
            isOwnProfile: false,
          ),
        ),
      );
    });
  }

  /// Hidden connect-by-code dialog (long-press on the radar). The code is the
  /// same rotating server token that BLE advertises — connecting still
  /// requires an active session on BOTH sides, so nothing is weakened.
  Future<void> _showManualDialog() async {
    if (_phase != _Phase.searching && _phase != _Phase.choose) return;
    if (_token == null) return;
    HapticFeedback.mediumImpact();
    final ctrl = TextEditingController();
    final c = context.k;
    final token = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF14161D),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(context.t('nearbyTitle'),
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('${context.t('nearbyMyCode')}: ',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 13.5)),
            SelectableText(_token!,
                style: TextStyle(
                    color: c.accent2,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy_rounded,
                  color: Colors.white54, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _token!));
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.t('nearbyCodeCopied'))));
              },
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white, letterSpacing: 1.2),
            decoration: InputDecoration(
              hintText: context.t('nearbyEnterCode'),
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('✕', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.accentFill),
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: Text(context.t('nearbyConnectBtn')),
          ),
        ],
      ),
    );
    if (token == null || token.isEmpty || !mounted) return;
    await _manualConnect(token);
  }

  Future<void> _manualConnect(String token) async {
    if (token == _token) return;
    final profile = await ApiService.nearbyPeek(token);
    if (!mounted) return;
    if (profile == null) {
      setState(() => _lostVisible = true);
      _lostBanner?.cancel();
      _lostBanner = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _lostVisible = false);
      });
      return;
    }
    _peers[token] = profile;
    _connect(token);
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
            _topBar(c),
            const Spacer(),
            // Long-press the stage → hidden connect-by-code dialog (lets you
            // test the whole exchange with a single phone, and doubles as a
            // fallback when BLE misbehaves on some device).
            GestureDetector(
              onLongPress: _showManualDialog,
              child: SizedBox(height: 340, child: _stage(c)),
            ),
            const Spacer(),
            _bottom(c),
            const SizedBox(height: 26),
          ]),
          if (_phase == _Phase.choose) _chooseSheet(c),
          // AirDrop-style announcement: the island grows out of the top the
          // moment somebody is found, instead of the user having to notice a
          // change down in the stage.
          IslandBanner(
            visible: _islandPeer != null,
            accent: c.accent,
            leading: _islandPeer == null
                ? null
                : _avatar(_islandPeer!, 46),
            title: _islandPeer == null
                ? ''
                : (_islandPeer!['username'] ?? '').toString(),
            subtitle: context.t('nearbyFoundSubtitle'),
            actionLabel: context.t('nearbyConnectAction'),
            onAction: _connectFromIsland,
            onDismiss: () => setState(() => _islandPeer = null),
          ),
        ]),
      ),
    );
  }

  /// Connect to whoever the island is currently announcing.
  void _connectFromIsland() {
    final peer = _islandPeer;
    if (peer == null) return;
    final token = _peers.entries
        .firstWhere((e) => e.value['id'] == peer['id'],
            orElse: () => const MapEntry('', {}))
        .key;
    setState(() => _islandPeer = null);
    if (token.isEmpty) return;
    _autoConnect?.cancel();
    _connect(token);
  }

  Widget _topBar(BrutalColors c) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 20, 0),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          ShaderMask(
            shaderCallback: (r) => LinearGradient(
              colors: [c.accent, const Color(0xFF7FB4FF)],
            ).createShader(r),
            child: Text(
              context.t('nearbyTitle'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4),
            ),
          ),
        ]),
      );

  /// The central animated stage: waves + rings + avatars.
  Widget _stage(BrutalColors c) {
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _pulse, _join, _burst]),
      builder: (_, __) {
        final joined = Curves.easeInOutCubic.transform(_join.value);
        final breath =
            1 + 0.035 * math.sin(_pulse.value * 2 * math.pi) * (1 - joined);
        return Stack(alignment: Alignment.center, children: [
          // soft breathing glow backdrop
          Transform.scale(
            scale: breath,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  c.accent.withOpacity(_excited ? 0.30 : 0.16),
                  c.accent.withOpacity(0.0),
                ]),
              ),
            ),
          ),
          CustomPaint(
            size: const Size(340, 340),
            painter: _WavesPainter(
              spin: _spin.value,
              pulse: _pulse.value,
              accent: c.accent,
              excited: _excited,
            ),
          ),
          if (_burst.value > 0 && _burst.value < 1)
            CustomPaint(
              size: const Size(340, 340),
              painter: _BurstPainter(t: _burst.value, accent: c.accent),
            ),
          // energy line between the two avatars while connecting
          if (_partner != null && joined > 0)
            CustomPaint(
              size: const Size(340, 340),
              painter: _LinkPainter(
                progress: joined,
                glow: _phase == _Phase.connected ? 1.0 : 0.55,
                accent: c.accent,
              ),
            ),
          // my avatar — slides slightly left as the link forms
          Transform.translate(
            offset: Offset(-56 * joined, 0),
            child: Transform.scale(
              scale: breath,
              child: _avatar(widget.user, 92 - 12 * joined),
            ),
          ),
          // partner avatar — flies in from the top, then meets mine
          if (_partner != null)
            Transform.translate(
              offset: Offset(56 * joined, -120 * (1 - joined)),
              child: Opacity(
                opacity: (0.25 + 0.75 * joined).clamp(0.0, 1.0),
                child: _avatar(_partner!, 92 - 12 * joined),
              ),
            ),
          // success check
          if (_phase == _Phase.connected)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              builder: (_, v, __) => Transform.scale(
                scale: v,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [c.accent, const Color(0xFF6FD2FF)]),
                    boxShadow: [
                      BoxShadow(
                          color: c.accent.withOpacity(0.75),
                          blurRadius: 34,
                          spreadRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 34),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Widget _avatar(Map u, double size) {
    final url = (u['avatar_url'] ?? u['avatar'] ?? '').toString();
    final letter =
        ((u['username'] ?? '?').toString().isEmpty ? '?' : (u['username'] ?? '?').toString()[0])
            .toUpperCase();
    final c = context.k;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.85), width: 2.5),
        boxShadow: [
          BoxShadow(
              color: c.accent.withOpacity(0.55),
              blurRadius: 30,
              spreadRadius: 2),
        ],
      ),
      child: ClipOval(
        child: url.isEmpty
            ? Container(
                color: const Color(0xFF1B2030),
                alignment: Alignment.center,
                child: Text(letter,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.38,
                        fontWeight: FontWeight.w800)),
              )
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
      ),
    );
  }

  Widget _bottom(BrutalColors c) {
    final style13 = TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13.5);
    Widget content;
    switch (_phase) {
      case _Phase.boot:
        content = const SizedBox(height: 64);
        break;
      case _Phase.perms:
        // Three genuinely different dead ends, each needing a different action:
        // the location switch is off, the OS won't prompt again, or the user
        // just declined once and a retry will re-prompt.
        content = Column(children: [
          Text(
              _locationServiceOff
                  ? context.t('nearbyLocationOff')
                  : context.t('nearbyPerms'),
              textAlign: TextAlign.center,
              style: style13),
          const SizedBox(height: 12),
          if (_locationServiceOff)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.accentFill),
              onPressed: () async {
                await openAppSettings();
              },
              child: Text(context.t('nearbyOpenLocationSettings')),
            )
          else if (_permsPermanentlyDenied)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.accentFill),
              onPressed: () async {
                await openAppSettings();
              },
              child: Text(context.t('nearbyOpenSettings')),
            ),
          TextButton(
            onPressed: () => setState(() {
              _phase = _Phase.boot;
              _start();
            }),
            child: Text(context.t('retryBtn'),
                style: TextStyle(color: c.accent2)),
          ),
        ]);
        break;
      case _Phase.error:
        content = Column(children: [
          Text(_error, textAlign: TextAlign.center, style: style13),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _phase = _Phase.boot;
              _start();
            }),
            child: Text(context.t('retryBtn'),
                style: TextStyle(color: c.accent2)),
          ),
        ]);
        break;
      case _Phase.connecting:
        content = _statusBlock(
            title: '${_partner?['username'] ?? ''}',
            sub: context.t('nearbyConnecting'),
            spinner: true);
        break;
      case _Phase.connected:
        content = _statusBlock(
            title: context.t('nearbyConnected'),
            sub: '${context.t('nearbyMutual')}  ·  +5 Aura ⚡');
        break;
      default:
        content = Column(children: [
          if (_lostVisible) ...[
            Text(context.t('nearbyLost'),
                style: const TextStyle(
                    color: Color(0xFFFF8A8A),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
            Text(context.t('nearbyLostHint'), style: style13),
            const SizedBox(height: 10),
          ],
          Text(context.t('nearbyHint'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(width: 9),
            Text(context.t('nearbySearching'), style: style13),
          ]),
          const SizedBox(height: 6),
          Text(context.t('nearbyOpenBoth'),
              style: TextStyle(
                  color: Colors.white.withOpacity(0.35), fontSize: 12)),
        ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250), child: content),
    );
  }

  Widget _statusBlock(
      {required String title, required String sub, bool spinner = false}) {
    final c = context.k;
    return Column(key: ValueKey(title), children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (spinner) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
          const SizedBox(width: 9),
        ],
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 7),
      Text(sub,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.5)),
    ]);
  }

  /// Bottom card list when several Sigmacta users are around.
  Widget _chooseSheet(BrutalColors c) {
    final entries = _peers.entries.toList();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF14161D).withOpacity(0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.09)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(context.t('nearbyWho'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final token = entries[i].key;
                final p = entries[i].value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _avatar(p, 44),
                  title: Text('@${p['username'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: Text((p['bio'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accentFill,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16)),
                    onPressed: () => _connect(token),
                    child: Text(context.t('nearbyConnectBtn'),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Rotating luminous arcs + expanding waves around the centre — the "radar".
class _WavesPainter extends CustomPainter {
  final double spin; // 0..1
  final double pulse; // 0..1
  final Color accent;
  final bool excited;
  _WavesPainter(
      {required this.spin,
      required this.pulse,
      required this.accent,
      required this.excited});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final speed = excited ? 2.0 : 1.0;

    // expanding waves
    for (var i = 0; i < 3; i++) {
      final t = ((pulse * speed) + i / 3) % 1.0;
      final r = 60 + t * 110;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withOpacity((1 - t) * (excited ? 0.5 : 0.3));
      canvas.drawCircle(c, r, p);
    }

    // rotating gradient arcs + a glowing "comet" particle on each ring
    for (var ring = 0; ring < 3; ring++) {
      final radius = 78.0 + ring * 26;
      final dir = ring.isEven ? 1.0 : -1.0;
      final start = spin * 2 * math.pi * dir * speed + ring * 1.7;
      final sweep = math.pi * (excited ? 1.15 : 0.85);
      final rect = Rect.fromCircle(center: c, radius: radius);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.4 - ring * 0.5
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [accent.withOpacity(0), accent.withOpacity(excited ? 0.95 : 0.6)],
          transform: GradientRotation(start),
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, false, p);

      // comet head at the bright end of the arc
      final a = start + sweep;
      final head = Offset(
          c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
      canvas.drawCircle(
          head,
          3.4 - ring * 0.6,
          Paint()
            ..color = Colors.white.withOpacity(excited ? 0.95 : 0.7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
      canvas.drawCircle(
          head,
          7.0 - ring * 1.2,
          Paint()
            ..color = accent.withOpacity(0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }

    // faint drifting sparks between the rings (premium dust)
    var s = 12345;
    for (var i = 0; i < 14; i++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final ang = (s % 1000) / 1000 * 2 * math.pi +
          spin * 2 * math.pi * (i.isEven ? 0.5 : -0.35);
      final rr = 66 + (s % 97);
      final tw = 0.35 + 0.65 * math.sin((pulse + i / 14) * 2 * math.pi).abs();
      canvas.drawCircle(
          Offset(c.dx + rr * math.cos(ang), c.dy + rr * math.sin(ang)),
          1.4,
          Paint()..color = accent.withOpacity(0.35 * tw));
    }
  }

  @override
  bool shouldRepaint(_WavesPainter o) =>
      o.spin != spin || o.pulse != pulse || o.excited != excited;
}

/// Radial particle burst + expanding ring when the connection succeeds.
class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Color accent;
  _BurstPainter({required this.t, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final e = Curves.easeOutCubic.transform(t);
    // expanding ring
    canvas.drawCircle(
        c,
        30 + e * 130,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - e) + 0.5
          ..color = accent.withOpacity((1 - e) * 0.8));
    // flying particles
    var s = 7777;
    for (var i = 0; i < 18; i++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final ang = i / 18 * 2 * math.pi + (s % 100) / 300;
      final dist = (36 + (s % 60)) + e * (90 + (s % 70));
      final r = 2.6 * (1 - e) + 0.4;
      canvas.drawCircle(
          Offset(c.dx + dist * math.cos(ang), c.dy + dist * math.sin(ang)),
          r,
          Paint()
            ..color = (i % 3 == 0 ? Colors.white : accent)
                .withOpacity((1 - e).clamp(0.0, 1.0)));
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.t != t;
}

/// The blue energy line joining the two avatars.
class _LinkPainter extends CustomPainter {
  final double progress; // 0..1
  final double glow;
  final Color accent;
  _LinkPainter(
      {required this.progress, required this.glow, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final cx = size.width / 2;
    const half = 56.0;
    final a = Offset(cx - half + 34, cy);
    final b = Offset(cx + half - 34, cy);
    final mid = Offset.lerp(a, b, 0.5)!;
    final pGlow = Paint()
      ..color = accent.withOpacity(0.35 * glow * progress)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final pCore = Paint()
      ..color = Colors.white.withOpacity(0.9 * progress)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.lerp(mid, a, progress)!,
        Offset.lerp(mid, b, progress)!, pGlow);
    canvas.drawLine(Offset.lerp(mid, a, progress)!,
        Offset.lerp(mid, b, progress)!, pCore);
  }

  @override
  bool shouldRepaint(_LinkPainter o) =>
      o.progress != progress || o.glow != glow;
}
