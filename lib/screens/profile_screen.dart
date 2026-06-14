import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/brutal.dart';
import 'chat_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Map user;
  final String? targetUserId;
  final bool isOwnProfile;
  const ProfileScreen(
      {Key? key,
      required this.user,
      this.targetUserId,
      this.isOwnProfile = true})
      : super(key: key);
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map userProfile = {};
  List userPosts = [];
  bool isLoading = false;
  bool isEditing = false;
  bool isFollowing = false;
  bool isUploadingAvatar = false;

  late final TextEditingController _usernameCtrl;
  late final TextEditingController _headlineCtrl;
  late final TextEditingController _aboutCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _workCtrl;
  late final TextEditingController _websiteCtrl;

  String get _targetId =>
      widget.isOwnProfile ? widget.user['id'] : widget.targetUserId!;

  // ─── REPUTATION & TIER (derived from activity — no backend needed) ──────────
  int get _totalLikes =>
      userPosts.fold<int>(0, (s, p) => s + ((p['likes_count'] ?? 0) as int));
  int get _postCount => userPosts.length;
  int get _followers => (userProfile['followers_count'] ?? 0) as int;

  int get _resonance => (_totalLikes * 6 + _postCount * 3).clamp(0, 100).toInt();
  int get _influence => (_followers * 7 + _postCount * 2).clamp(0, 100).toInt();
  int get _reliability {
    var s = 35 + _postCount * 4;
    if ((userProfile['avatar_url'] ?? '').toString().isNotEmpty) s += 15;
    if ((userProfile['about'] ?? userProfile['bio'] ?? '')
        .toString()
        .trim()
        .isNotEmpty) s += 15;
    if ((userProfile['headline'] ?? '').toString().trim().isNotEmpty) s += 10;
    return s.clamp(0, 100).toInt();
  }

  int get _power => _totalLikes + _followers * 2 + _postCount * 3;
  // 0 = Newcomer · 1 = Active · 2 = Top author
  int get _tier => _power >= 40 ? 2 : (_power >= 12 ? 1 : 0);

  @override
  void initState() {
    super.initState();
    userProfile = widget.isOwnProfile ? Map.from(widget.user) : {};
    _usernameCtrl = TextEditingController();
    _headlineCtrl = TextEditingController();
    _aboutCtrl = TextEditingController();
    _locationCtrl = TextEditingController();
    _workCtrl = TextEditingController();
    _websiteCtrl = TextEditingController();
    _syncControllers();
    _loadProfile();
    _loadPosts();
    if (!widget.isOwnProfile) _checkFollow();
  }

  void _syncControllers() {
    _usernameCtrl.text = userProfile['username'] ?? '';
    _headlineCtrl.text = userProfile['headline'] ?? '';
    _aboutCtrl.text = userProfile['about'] ?? userProfile['bio'] ?? '';
    _locationCtrl.text = userProfile['location'] ?? '';
    _workCtrl.text = userProfile['work'] ?? '';
    _websiteCtrl.text = userProfile['website'] ?? '';
  }

  Future<void> _loadProfile() async {
    final data = await ApiService.getUser(_targetId);
    if (data['success'] == true && mounted) {
      setState(() {
        userProfile = data['data'];
        _syncControllers();
      });
    }
  }

  Future<void> _loadPosts() async {
    setState(() => isLoading = true);
    final all = await ApiService.getPosts(widget.user['id']);
    if (mounted) {
      setState(() {
        userPosts = all.where((p) => p['user_id'] == _targetId).toList();
        isLoading = false;
      });
    }
  }

  Future<void> _checkFollow() async {
    final result =
        await ApiService.isFollowing(widget.user['id'], widget.targetUserId!);
    if (mounted) setState(() => isFollowing = result);
  }

  Future<void> _toggleFollow() async {
    final fn = isFollowing ? ApiService.unfollow : ApiService.follow;
    final data = await fn(widget.user['id'], widget.targetUserId!);
    if (data['success'] == true && mounted) {
      setState(() {
        isFollowing = !isFollowing;
        userProfile['followers_count'] = isFollowing
            ? (userProfile['followers_count'] ?? 0) + 1
            : ((userProfile['followers_count'] ?? 1) - 1).clamp(0, 99999);
      });
    }
  }

  Future<void> _saveProfile() async {
    final data = await ApiService.updateUser(widget.user['id'], {
      'username': _usernameCtrl.text.trim(),
      'headline': _headlineCtrl.text.trim(),
      'about': _aboutCtrl.text.trim(),
      'location': _locationCtrl.text.trim(),
      'work': _workCtrl.text.trim(),
      'website': _websiteCtrl.text.trim(),
    });
    if (data['success'] == true && mounted) {
      setState(() {
        isEditing = false;
        userProfile['username'] = _usernameCtrl.text.trim();
        userProfile['headline'] = _headlineCtrl.text.trim();
        userProfile['about'] = _aboutCtrl.text.trim();
        userProfile['location'] = _locationCtrl.text.trim();
        userProfile['work'] = _workCtrl.text.trim();
        userProfile['website'] = _websiteCtrl.text.trim();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80);
    if (file == null) return;
    setState(() => isUploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final uploaded = await ApiService.uploadMedia(
        bytes,
        folder: 'avatar',
        ext: 'jpg',
        contentType: 'image/jpeg',
        userId: widget.user['id'].toString(),
      );
      if (uploaded != null) {
        final url = '$uploaded?t=${DateTime.now().millisecondsSinceEpoch}';
        await ApiService.updateUser(widget.user['id'], {'avatar_url': url});
        if (mounted) setState(() => userProfile['avatar_url'] = url);
      }
    } catch (_) {}
    if (mounted) setState(() => isUploadingAvatar = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (widget.isOwnProfile)
            IconButton(
              icon: Icon(isEditing ? Icons.check_rounded : Icons.edit_rounded,
                  color: isEditing ? c.accent : c.ink),
              onPressed: () {
                if (isEditing) {
                  _saveProfile();
                } else {
                  setState(() => isEditing = true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _headerCard(c),
          const SizedBox(height: 14),
          _reputationCard(c),
          const SizedBox(height: 14),
          if (isEditing || (_aboutCtrl.text.trim().isNotEmpty))
            _aboutCard(c),
          if (isEditing ||
              _locationCtrl.text.trim().isNotEmpty ||
              _workCtrl.text.trim().isNotEmpty ||
              _websiteCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _detailsCard(c),
          ],
          const SizedBox(height: 14),
          _postsCard(c),
        ],
      ),
    );
  }

  // ─── HEADER ─────────────────────────────────────────────────────────────────
  Widget _headerCard(BrutalColors c) {
    final avatarUrl = userProfile['avatar_url'];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _tierDecoration(c, _tier),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.isOwnProfile ? _pickAvatar : null,
            child: Stack(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: avatarUrl == null ? c.buttonGradient : null,
                    shape: BoxShape.circle,
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(avatarUrl),
                            fit: BoxFit.cover)
                        : null,
                    border: Border.all(color: c.ink.withOpacity(0.08), width: 2),
                  ),
                  child: avatarUrl == null
                      ? const Icon(Icons.person_rounded,
                          size: 46, color: Colors.white)
                      : null,
                ),
                if (widget.isOwnProfile)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2),
                      ),
                      child: isUploadingAvatar
                          ? const Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.camera_alt_rounded,
                              size: 15, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!isEditing) ...[
            Text(
              userProfile['username'] ?? 'User',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: c.ink),
            ),
            if ((userProfile['headline'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                userProfile['headline'],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: c.inkSoft, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 10),
            _tierBadge(c, _tier),
          ] else ...[
            _editField(c, _usernameCtrl, 'Username'),
            const SizedBox(height: 10),
            _editField(c, _headlineCtrl, 'Headline (e.g. Founder @ Sigma)'),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(c, userPosts.length.toString(), 'Posts'),
              _stat(c, '${userProfile['followers_count'] ?? 0}', 'Followers'),
              _stat(c, '${userProfile['following_count'] ?? 0}', 'Following'),
            ],
          ),
          if (!widget.isOwnProfile) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _actionBtn(
                    c,
                    label: isFollowing ? 'Following' : 'Follow',
                    filled: !isFollowing,
                    onTap: _toggleFollow,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionBtn(
                    c,
                    label: 'Message',
                    filled: false,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          chat: {'name': userProfile['username']},
                          user: widget.user,
                          targetUser: userProfile,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _aboutCard(BrutalColors c) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(c, 'About'),
          const SizedBox(height: 10),
          if (!isEditing)
            Text(
              _aboutCtrl.text.trim().isEmpty ? '—' : _aboutCtrl.text.trim(),
              style: TextStyle(color: c.ink, fontSize: 14, height: 1.5),
            )
          else
            _editField(c, _aboutCtrl, 'Tell people about yourself', maxLines: 4),
        ],
      ),
    );
  }

  Widget _detailsCard(BrutalColors c) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(c, 'Details'),
          const SizedBox(height: 12),
          if (!isEditing) ...[
            _detailRow(c, Icons.work_outline_rounded, _workCtrl.text),
            _detailRow(c, Icons.location_on_outlined, _locationCtrl.text),
            _detailRow(c, Icons.link_rounded, _websiteCtrl.text),
          ] else ...[
            _editField(c, _workCtrl, 'Work (e.g. CEO at Acme)'),
            const SizedBox(height: 10),
            _editField(c, _locationCtrl, 'Location'),
            const SizedBox(height: 10),
            _editField(c, _websiteCtrl, 'Website'),
          ],
        ],
      ),
    );
  }

  Widget _postsCard(BrutalColors c) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(c, 'Posts'),
          const SizedBox(height: 10),
          if (isLoading)
            Center(
                child: Padding(
              padding: const EdgeInsets.all(16),
              child: CircularProgressIndicator(color: c.accent),
            ))
          else if (userPosts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No posts yet',
                  style: TextStyle(color: c.inkSoft, fontSize: 14)),
            )
          else
            ...userPosts.map((post) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post['content'] ?? '',
                          style: TextStyle(fontSize: 15, color: c.ink)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.favorite_rounded,
                            size: 14, color: c.danger),
                        const SizedBox(width: 5),
                        Text('${post['likes_count'] ?? 0}',
                            style:
                                TextStyle(color: c.inkSoft, fontSize: 12)),
                      ]),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  // ─── small pieces ─────────────────────────────────────────────────────────
  Widget _sectionTitle(BrutalColors c, String t) => Text(
        t,
        style:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
      );

  Widget _stat(BrutalColors c, String value, String label) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: c.ink)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: c.inkSoft, fontSize: 12)),
        ],
      );

  Widget _detailRow(BrutalColors c, IconData icon, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.inkSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                style: TextStyle(color: c.ink, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _editField(BrutalColors c, TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      textAlign: maxLines == 1 ? TextAlign.center : TextAlign.start,
      style: TextStyle(color: c.ink, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: c.surface2,
        hintStyle: TextStyle(color: c.inkSoft, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _actionBtn(BrutalColors c,
      {required String label,
      required bool filled,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(13),
          border: filled ? null : Border.all(color: c.ink.withOpacity(0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? c.onAccent : c.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // ─── REPUTATION / TIER UI ───────────────────────────────────────────────────
  BoxDecoration _tierDecoration(BrutalColors c, int tier) {
    if (tier >= 2) {
      return BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.accent.withOpacity(0.22),
            c.accent3.withOpacity(0.16),
            c.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withOpacity(0.45), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: c.accent.withOpacity(0.22),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      );
    }
    if (tier == 1) {
      return BoxDecoration(
        gradient: LinearGradient(
          colors: [c.accent.withOpacity(0.10), c.surface],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withOpacity(0.20)),
        boxShadow: [
          BoxShadow(color: c.shadow, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      );
    }
    return BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: c.shadow, blurRadius: 8, offset: const Offset(0, 2)),
      ],
    );
  }

  Widget _tierBadge(BrutalColors c, int tier) {
    final ru = AppScope.of(context).lang == 'ru';
    IconData icon;
    String label;
    Color col;
    if (tier >= 2) {
      icon = Icons.workspace_premium_rounded;
      label = ru ? 'Топ-автор' : 'Top author';
      col = c.accent;
    } else if (tier == 1) {
      icon = Icons.bolt_rounded;
      label = ru ? 'Активный' : 'Active';
      col = c.accent2;
    } else {
      icon = Icons.spa_rounded;
      label = ru ? 'Новичок' : 'Newcomer';
      col = c.inkSoft;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: col.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: col.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: col),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: col, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _reputationCard(BrutalColors c) {
    final ru = AppScope.of(context).lang == 'ru';
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(c, ru ? 'Репутация' : 'Reputation'),
          const SizedBox(height: 14),
          _repRow(c, ru ? 'Резонанс' : 'Resonance', _resonance, c.accent),
          const SizedBox(height: 12),
          _repRow(c, ru ? 'Влияние' : 'Influence', _influence, c.accent2),
          const SizedBox(height: 12),
          _repRow(c, ru ? 'Надёжность' : 'Reliability', _reliability, c.accent3),
        ],
      ),
    );
  }

  Widget _repRow(BrutalColors c, String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: TextStyle(
                  color: c.ink, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$value',
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value / 100,
            minHeight: 8,
            backgroundColor: c.surface2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _headlineCtrl.dispose();
    _aboutCtrl.dispose();
    _locationCtrl.dispose();
    _workCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }
}
