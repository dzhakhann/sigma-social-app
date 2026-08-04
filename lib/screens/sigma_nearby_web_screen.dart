import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../services/nearby_store.dart';
import '../services/socket_service.dart';
import '../theme/brutal_theme.dart';
import 'profile_screen.dart';

/// Sigma Nearby's web replacement — same server-side exchange (mutual follow
/// + Aura, both sides must have the screen open), same rotating token, just
/// swapping the transport: native discovers a nearby phone over Bluetooth/
/// Wi-Fi Direct, which Safari on iOS has no API for at all — there is no
/// workaround for that inside a browser, so the token has to travel some
/// other way a person can actually do. A QR code (or reading the digits out
/// loud) does the same job: show it, they scan or type it, done.
///
/// Reuses exactly the endpoints the native screen does — nearbyStart/
/// nearbyPeek/nearbyConnect never cared HOW the token reached the other
/// device, only that both sides have an active session.
class SigmaNearbyWebScreen extends StatefulWidget {
  final Map user;
  const SigmaNearbyWebScreen({super.key, required this.user});

  @override
  State<SigmaNearbyWebScreen> createState() => _SigmaNearbyWebScreenState();
}

class _SigmaNearbyWebScreenState extends State<SigmaNearbyWebScreen> {
  int _mode = 0; // 0 = show my code, 1 = scan/enter theirs
  String? _token;
  Timer? _rotateTimer;
  bool _connecting = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _startToken();
    // The passive side (whoever's QR got scanned) learns about the completed
    // exchange over the socket, exactly like the native screen.
    final uid = (widget.user['id'] ?? '').toString();
    SocketService().connect(uid);
    SocketService().onNearbyConnected = (data) {
      final them = data['user'];
      if (them is Map && !_handled && mounted) _onPaired(Map.from(them));
    };
  }

  Future<void> _startToken() async {
    final t = await ApiService.nearbyStart();
    if (!mounted) return;
    setState(() => _token = t);
    // Server TTL is 2 minutes — matches the native screen's rotation cadence.
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(const Duration(seconds: 90), (_) async {
      final t = await ApiService.nearbyStart();
      if (mounted && t != null) setState(() => _token = t);
    });
  }

  @override
  void dispose() {
    _rotateTimer?.cancel();
    SocketService().onNearbyConnected = null;
    ApiService.nearbyStop();
    super.dispose();
  }

  Future<void> _connectToken(String raw) async {
    final token = raw.trim();
    if (token.isEmpty || token == _token || _connecting || _handled) return;
    setState(() => _connecting = true);
    final profile = await ApiService.nearbyPeek(token);
    if (!mounted) return;
    if (profile == null) {
      setState(() => _connecting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('nearbyErrGeneric'))));
      return;
    }
    final them = await ApiService.nearbyConnect(token);
    if (!mounted) return;
    if (them == null) {
      setState(() => _connecting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('nearbyStartFailed'))));
      return;
    }
    _onPaired(them);
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled || _connecting) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _connectToken(raw);
      return;
    }
  }

  void _onPaired(Map them) {
    _handled = true;
    _rotateTimer?.cancel();
    HapticFeedback.mediumImpact();
    NearbyStore.add(them); // same "Recent connections" list the native flow feeds
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          user: widget.user,
          targetUserId: (them['id'] ?? '').toString(),
          isOwnProfile: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text(context.t('nearbyTitle')),
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            _tab(c, 0, Icons.qr_code_2_rounded, context.t('myQr')),
            _tab(c, 1, Icons.qr_code_scanner_rounded, context.t('scanQr')),
          ]),
        ),
        Expanded(child: _mode == 0 ? _myCode(c) : _scanner(c)),
      ]),
    );
  }

  Widget _tab(BrutalColors c, int i, IconData icon, String label) {
    final sel = _mode == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: sel ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(11)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: sel ? c.onAccent : c.inkSoft),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: sel ? c.onAccent : c.inkSoft,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _myCode(BrutalColors c) {
    final token = _token;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: token == null
                ? const SizedBox(
                    width: 230,
                    height: 230,
                    child: Center(child: CircularProgressIndicator()))
                : QrImageView(
                    data: token,
                    version: QrVersions.auto,
                    size: 230,
                    backgroundColor: Colors.white,
                  ),
          ),
          const SizedBox(height: 20),
          if (token != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(token,
                    style: TextStyle(
                        color: c.accent2,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: c.inkSoft, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: token));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.t('nearbyCodeCopied'))));
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              context.t('nearbyWebShowHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanner(BrutalColors c) {
    final ctrl = TextEditingController();
    return Column(children: [
      Expanded(
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MobileScanner(onDetect: _onDetect),
              ),
            ),
            Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                border: Border.all(color: c.accent, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            if (_connecting)
              Container(
                color: Colors.black45,
                child: Center(
                    child: CircularProgressIndicator(color: c.accent)),
              ),
            Positioned(
              bottom: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(context.t('qrScanHint'),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
      // Camera access can be flaky/denied in a browser — typing the code the
      // other person is showing works every time, so it's always available,
      // not hidden behind a long-press the way the native screen's fallback is.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: TextStyle(color: c.ink, letterSpacing: 1.2),
              decoration: InputDecoration(
                hintText: context.t('nearbyEnterCode'),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: _connectToken,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.accentFill),
            onPressed: _connecting ? null : () => _connectToken(ctrl.text),
            child: Text(context.t('nearbyConnectBtn')),
          ),
        ]),
      ),
    ]);
  }
}
