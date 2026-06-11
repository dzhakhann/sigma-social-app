import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../constants.dart' show kSupabaseUrl, kSupabaseKey;
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//  HOME · "PULSE"
//  Not a feed clone — a tactile board with an ENERGY meter + streak that grow
//  as you interact. Oversized, satisfying reaction blocks = dopamine.
// ════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  final Map user;
  const HomeScreen({super.key, required this.user});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List _posts = [];
  bool _loading = false;

  // dopamine state
  double _energy = 0.12;
  int _streak = 1;
  bool _postedToday = false;

  final _composerCtrl = TextEditingController();
  String? _imageB64;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ApiService.getPosts(widget.user['id']);
    if (mounted) {
      setState(() {
        _posts = data;
        _loading = false;
      });
    }
  }

  void _addEnergy(double amount) {
    HapticFeedback.lightImpact();
    setState(() => _energy = (_energy + amount).clamp(0.0, 1.0));
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageB64 = base64Encode(bytes));
  }

  Future<void> _drop() async {
    if (_composerCtrl.text.trim().isEmpty && _imageB64 == null) return;
    setState(() => _posting = true);
    try {
      String? imageUrl;
      if (_imageB64 != null) {
        final name =
            '${widget.user['id']}_post_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final res = await http.put(
          Uri.parse('$kSupabaseUrl/storage/v1/object/avatars/$name'),
          headers: {
            'Authorization': 'Bearer $kSupabaseKey',
            'Content-Type': 'image/jpeg',
            'x-upsert': 'true',
          },
          body: base64Decode(_imageB64!),
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          imageUrl = '$kSupabaseUrl/storage/v1/object/public/avatars/$name';
        }
      }
      await ApiService.createPost(widget.user['id'], _composerCtrl.text.trim(),
          imageUrl: imageUrl);
      _composerCtrl.clear();
      setState(() {
        _imageB64 = null;
        if (!_postedToday) {
          _postedToday = true;
          _streak += 1;
        }
      });
      _addEnergy(0.18);
      await _load();
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          backgroundColor: c.surface,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(c)),
              SliverToBoxAdapter(child: _energyPanel(c)),
              SliverToBoxAdapter(child: _composer(c)),
              if (_loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Center(
                        child: CircularProgressIndicator(color: c.accent2)),
                  ),
                )
              else if (_posts.isEmpty)
                SliverToBoxAdapter(child: _empty(c))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _PulseCard(
                        post: _posts[i],
                        user: widget.user,
                        onEnergy: _addEnergy,
                      ),
                    ),
                    childCount: _posts.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          // wordmark with an accent underline block
          Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Container(height: 10, color: c.accent.withOpacity(0.9)),
              ),
              Text(
                context.t('appName'),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: c.ink,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          BrutalTap(
            padding: const EdgeInsets.all(10),
            radius: 12,
            shadowOffset: const Offset(3, 3),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SettingsScreen(user: widget.user)),
            ),
            child: Icon(Icons.tune_rounded, color: c.ink, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _energyPanel(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: BrutalCard(
        fill: c.surface,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BrutalLabel(context.t('energy')),
                const Spacer(),
                Text(
                  '${(_energy * 100).round()}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16, color: c.ink),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // energy track
            LayoutBuilder(
              builder: (context, cons) {
                return Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.ink, width: 2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutBack,
                      width: (cons.maxWidth - 4) * _energy,
                      height: 14,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.ink, width: 1.5),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: c.accent3, size: 20),
                const SizedBox(width: 6),
                Text(
                  '$_streak ${context.t('days')} · ${context.t('streak')}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: c.inkSoft),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: BrutalCard(
        fill: c.surface,
        padding: const EdgeInsets.all(14),
        shadowOffset: const Offset(5, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _composerCtrl,
              maxLines: null,
              minLines: 1,
              style: TextStyle(
                  color: c.ink, fontSize: 17, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t('whatsUp'),
                hintStyle: TextStyle(
                    color: c.inkSoft, fontSize: 17, fontWeight: FontWeight.w600),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (_imageB64 != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(_imageB64!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                BrutalTap(
                  onTap: _pickImage,
                  padding: const EdgeInsets.all(10),
                  radius: 10,
                  shadowOffset: const Offset(3, 3),
                  child: Icon(Icons.add_photo_alternate_rounded,
                      color: c.accent2, size: 20),
                ),
                const Spacer(),
                BrutalTap(
                  onTap: _posting ? null : _drop,
                  fill: c.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  radius: 10,
                  shadowOffset: const Offset(4, 4),
                  child: _posting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: c.onAccent),
                        )
                      : Text(
                          context.t('drop'),
                          style: TextStyle(
                            color: c.onAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Icon(Icons.bolt_rounded, size: 64, color: c.accent),
          const SizedBox(height: 14),
          Text(
            context.t('nothingYet'),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 20, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            context.t('beFirst'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    super.dispose();
  }
}

// ─── PULSE CARD ───────────────────────────────────────────────────────────────
class _PulseCard extends StatefulWidget {
  final Map post;
  final Map user;
  final void Function(double) onEnergy;
  const _PulseCard(
      {required this.post, required this.user, required this.onEnergy});
  @override
  State<_PulseCard> createState() => _PulseCardState();
}

class _PulseCardState extends State<_PulseCard>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likes;
  int _boosts = 0;
  bool _boosted = false;
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _liked = widget.post['is_liked'] == true;
    _likes = (widget.post['likes_count'] ?? 0) as int;
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  Future<void> _react() async {
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += _liked ? 1 : -1;
    });
    if (_liked) {
      _pop.forward(from: 0);
      widget.onEnergy(0.06);
    }
    final res = await ApiService.likePost(
        widget.post['id'].toString(), widget.user['id'].toString());
    if (res['success'] == true && mounted) {
      setState(() {
        _likes = (res['likes_count'] ?? _likes) as int;
        _liked = res['liked'] == true;
      });
    }
  }

  void _boost() {
    setState(() {
      _boosted = !_boosted;
      _boosts += _boosted ? 1 : -1;
    });
    if (_boosted) widget.onEnergy(0.05);
  }

  String _time() {
    final raw = widget.post['created_at'];
    if (raw == null) return '';
    try {
      return timeago.format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final username = (widget.post['username'] ?? 'user').toString();
    final avatar = widget.post['user_avatar'] ?? widget.post['avatar_url'];
    final content = (widget.post['content'] ?? '').toString();
    final image = widget.post['image_url'];

    return BrutalCard(
      fill: c.surface,
      padding: EdgeInsets.zero,
      shadowOffset: const Offset(5, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // author
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    user: widget.user,
                    targetUserId: widget.post['user_id'],
                    isOwnProfile:
                        widget.post['user_id'] == widget.user['id'],
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.ink, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatar != null
                        ? CachedNetworkImage(
                            imageUrl: avatar.toString(), fit: BoxFit.cover)
                        : Icon(Icons.person_rounded, color: c.inkSoft),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@$username',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: c.ink),
                        ),
                        Text(
                          _time(),
                          style: TextStyle(fontSize: 11, color: c.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // content
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text(
                content,
                style: TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: c.ink),
              ),
            ),
          // image
          if (image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.ink, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: image.toString(),
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          // reactions
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.ink, width: 2)),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: _ReactBtn(
                    icon: _liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '$_likes',
                    active: _liked,
                    activeColor: c.danger,
                    pop: _pop,
                    onTap: _react,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReactBtn(
                    icon: Icons.mode_comment_outlined,
                    label: context.t('comment'),
                    active: false,
                    activeColor: c.accent2,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommentsScreen(
                            post: widget.post, user: widget.user),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ReactBtn(
                    icon: Icons.rocket_launch_rounded,
                    label: _boosts > 0 ? '$_boosts' : context.t('boost'),
                    active: _boosted,
                    activeColor: c.accent,
                    onTap: _boost,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }
}

class _ReactBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final AnimationController? pop;
  const _ReactBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
    this.pop,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final iconWidget = Icon(
      icon,
      size: 20,
      color: active ? c.onAccent : c.ink,
    );
    return BrutalTap(
      onTap: onTap,
      fill: active ? activeColor : c.surface,
      radius: 10,
      shadowOffset: const Offset(3, 3),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          pop != null
              ? ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.5).animate(
                    CurvedAnimation(parent: pop!, curve: Curves.elasticOut),
                  ),
                  child: iconWidget,
                )
              : iconWidget,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: active ? c.onAccent : c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
