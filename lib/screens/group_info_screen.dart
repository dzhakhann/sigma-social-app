import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;

import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/sigma_link.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'avatar_crop_screen.dart';
import 'photo_view_screen.dart';
import 'profile_screen.dart';
import 'sigma_gallery_screen.dart';

/// Full-screen group info — same shape as a user's ProfileScreen (big
/// centered avatar, name, stats line, description) instead of the bottom
/// sheet this replaces, per the "group info should open/look like a real
/// profile" request. Manages its own copy of the group/member data and
/// refreshes it on open; the caller (GroupChatScreen) re-syncs its own copy
/// when this screen is popped, since edits made here (rename, add/remove
/// member, promote/demote) don't propagate back automatically.
class GroupInfoScreen extends StatefulWidget {
  final Map user;
  final Map group;
  const GroupInfoScreen({super.key, required this.user, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late Map _group = widget.group;
  List members = [];
  bool _loading = true;

  String get _groupId => _group['id'].toString();
  String get _myId => widget.user['id'].toString();
  bool get _isAdmin => _group['my_role'] == 'admin';

  @override
  void initState() {
    super.initState();
    members = (widget.group['members'] as List?) ?? [];
    _refresh();
  }

  Future<void> _refresh() async {
    final detail = await ApiService.getGroup(_groupId);
    if (detail != null && mounted) {
      setState(() {
        _group = detail;
        members = (detail['members'] as List?) ?? [];
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('groupInfoTitle'),
            style: TextStyle(
                color: c.ink, fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          // Groups were the one shareable thing with no way to share it.
          IconButton(
            icon: Icon(Icons.share_rounded, color: c.ink, size: 20),
            onPressed: _shareGroup,
          ),
          IconButton(
            icon: Icon(Icons.link_rounded, color: c.ink, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _groupLink));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.t('linkCopied'))));
            },
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: c.accent, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(c),
                const Divider(height: 24),
                if (_isAdmin) ...[
                  ListTile(
                    leading: Icon(Icons.edit_outlined, color: c.ink),
                    title: Text(context.t('editGroupBtn'),
                        style: TextStyle(color: c.ink)),
                    onTap: _editGroupInfo,
                  ),
                  ListTile(
                    leading: Icon(Icons.person_add_rounded, color: c.accent),
                    title: Text(context.t('addMemberBtn'),
                        style: TextStyle(color: c.ink)),
                    onTap: _openAddMember,
                  ),
                  const Divider(height: 24),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                      context
                          .t('memberCountLabel')
                          .replaceAll('{n}', '${members.length}'),
                      style: TextStyle(
                          color: c.inkSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
                for (final m in members) _memberTile(c, m),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                    onPressed: () async {
                      await ApiService.removeGroupMember(_groupId, _myId);
                      if (mounted) {
                        Navigator.of(context).pop(); // info screen
                        Navigator.of(context).pop(); // chat screen
                      }
                    },
                    child: Text(context.t('leaveGroupBtn')),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(children: [
        _avatarBlock(c),
        const SizedBox(height: 12),
        Text((_group['name'] ?? '').toString(),
            style: TextStyle(
                color: c.ink, fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 4),
        Text(
            '${context.t('memberCountLabel').replaceAll('{n}', '${members.length}')} · '
            '${_group['is_open'] == true ? context.t('openGroupLabel') : context.t('closedGroupLabelShort')}',
            style: TextStyle(color: c.inkSoft, fontSize: 13)),
        if ((_group['description'] ?? '').toString().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(14),
            width: double.infinity,
            decoration: BoxDecoration(
                color: c.surface2, borderRadius: BorderRadius.circular(16)),
            child: Text(_group['description'].toString(),
                textAlign: TextAlign.start,
                style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.35)),
          ),
      ]),
    );
  }

  Widget _avatarBlock(BrutalColors c) {
    final avatarUrl = (_group['avatar_url'] ?? '').toString();
    final heroTag = 'group_avatar_$_groupId';
    return GestureDetector(
      // Tapping the photo itself opens it fullscreen (Telegram/profile
      // parity) — the edit pencil is a separate tap target so it doesn't get
      // shadowed by that for admins.
      onTap: avatarUrl.isNotEmpty
          ? () => Navigator.push(
              context, PhotoViewScreen.route(avatarUrl, heroTag: heroTag))
          : (_isAdmin ? _editGroupInfo : null),
      child: Stack(alignment: Alignment.center, children: [
        Hero(
          tag: heroTag,
          child: CircleAvatar(
            radius: 48,
            backgroundColor: c.surface2,
            backgroundImage: avatarUrl.isNotEmpty
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? Icon(Icons.groups_rounded, color: c.inkSoft, size: 42)
                : null,
          ),
        ),
        if (_isAdmin)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _editGroupInfo,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.accent,
                    border: Border.all(color: c.bg, width: 2)),
                child: const Icon(Icons.edit_rounded,
                    color: Colors.white, size: 15),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _memberTile(BrutalColors c, Map m) {
    final isMe = m['user_id'].toString() == _myId;
    final isAdmin = m['role'] == 'admin';
    return ListTile(
      onTap: isMe
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                      user: widget.user,
                      targetUserId: m['user_id'],
                      isOwnProfile: false))),
      leading: CircleAvatar(
        backgroundColor: c.surface2,
        backgroundImage: (m['avatar_url'] ?? '').toString().isNotEmpty
            ? CachedNetworkImageProvider(m['avatar_url'])
            : null,
        child: (m['avatar_url'] ?? '').toString().isEmpty
            ? Icon(Icons.person, color: c.inkSoft)
            : null,
      ),
      title: Text(
          '${m['username']}${isMe ? ' (${context.t('youLabel')})' : ''}',
          style: TextStyle(color: c.ink)),
      subtitle: isAdmin
          ? Text(context.t('adminLabel'),
              style: TextStyle(
                  color: c.accent, fontSize: 11.5, fontWeight: FontWeight.w700))
          : null,
      trailing: (_isAdmin && !isMe)
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: c.inkSoft),
              onSelected: (v) async {
                if (v == 'promote') {
                  await ApiService.promoteGroupAdmin(_groupId, m['user_id']);
                } else if (v == 'demote') {
                  await ApiService.demoteGroupAdmin(_groupId, m['user_id']);
                } else if (v == 'remove') {
                  await ApiService.removeGroupMember(_groupId, m['user_id']);
                }
                _refresh();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: isAdmin ? 'demote' : 'promote',
                    child: Text(isAdmin
                        ? context.t('demoteAdminBtn')
                        : context.t('promoteAdminBtn'))),
                PopupMenuItem(
                    value: 'remove', child: Text(context.t('removeMemberBtn'))),
              ],
            )
          : null,
    );
  }

  /// Canonical /g/<id> link — the same shape the router resolves, so a group
  /// link pasted anywhere opens the group rather than a web page.
  String get _groupLink => SigmaLink(SigmaLinkKind.group, _groupId).url;

  void _shareGroup() {
    final name = (_group['name'] ?? '').toString();
    Share.share(name.isEmpty ? _groupLink : '$name\n$_groupLink');
  }

  Future<void> _openAddMember() async {
    // Contacts (people you follow), same scope group creation uses — not
    // every account on the platform.
    final following = await ApiService.getFollowing(_myId, limit: 200);
    final memberIds = members.map((m) => m['user_id'].toString()).toSet();
    final candidates = following
        .where((u) => !memberIds.contains(u['id'].toString()))
        .toList();
    if (!mounted) return;
    final c = context.k;
    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: SizedBox(
          height: 420,
          child: candidates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(context.t('noContactsYet'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.inkSoft)),
                  ),
                )
              : ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final u = candidates[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: c.surface2,
                        backgroundImage: u['avatar_url'] != null
                            ? CachedNetworkImageProvider(u['avatar_url'])
                            : null,
                        child: u['avatar_url'] == null
                            ? Icon(Icons.person, color: c.inkSoft)
                            : null,
                      ),
                      title: Text((u['username'] ?? 'User').toString(),
                          style: TextStyle(color: c.ink)),
                      onTap: () async {
                        Navigator.pop(sheetCtx);
                        await ApiService.addGroupMember(
                            _groupId, u['id'].toString());
                        _refresh();
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _editGroupInfo() async {
    final c = context.k;
    final nameCtrl =
        TextEditingController(text: (_group['name'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (_group['description'] ?? '').toString());
    Uint8List? newAvatarBytes;
    final currentAvatarUrl = (_group['avatar_url'] ?? '').toString();
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                        color: c.ink.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2))),
                Text(context.t('editGroupBtn'),
                    style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    final picked = await Navigator.push<dynamic>(
                      sheetCtx,
                      MaterialPageRoute(
                          builder: (_) => const SigmaGalleryScreen(
                              type: RequestType.image)),
                    );
                    Uint8List? raw;
                    if (picked is Uint8List) {
                      raw = picked;
                    } else if (picked is List<Uint8List> && picked.isNotEmpty) {
                      raw = picked.first; // web: bytes read already, no dart:io File
                    } else if (picked is List<File> && picked.isNotEmpty) {
                      raw = await picked.first.readAsBytes();
                    }
                    if (raw == null) return;
                    final cropped = await Navigator.push<Uint8List>(
                      sheetCtx,
                      MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => AvatarCropScreen(imageBytes: raw!)),
                    );
                    if (cropped == null) return;
                    setSheetState(() => newAvatarBytes = cropped);
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: c.surface2,
                    backgroundImage: newAvatarBytes != null
                        ? MemoryImage(newAvatarBytes!)
                        : (currentAvatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(currentAvatarUrl)
                                as ImageProvider
                            : null),
                    child: newAvatarBytes == null && currentAvatarUrl.isEmpty
                        ? Icon(Icons.camera_alt_rounded,
                            color: c.inkSoft, size: 28)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: c.ink),
                  decoration: InputDecoration(
                    labelText: context.t('groupNameLabel'),
                    filled: true,
                    fillColor: c.surface2,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: TextStyle(color: c.ink),
                  decoration: InputDecoration(
                    labelText: context.t('groupDescLabel'),
                    filled: true,
                    fillColor: c.surface2,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accentFill,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            String? avatarUrl;
                            if (newAvatarBytes != null) {
                              avatarUrl = await ApiService.uploadMedia(
                                  newAvatarBytes!,
                                  folder: 'group',
                                  ext: 'png',
                                  contentType: 'image/png',
                                  userId: _myId);
                            }
                            await ApiService.updateGroup(_groupId,
                                name: nameCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                avatarUrl: avatarUrl);
                            await _refresh();
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          },
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(context.t('saveBtn')),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
