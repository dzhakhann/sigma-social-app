import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart' show RequestType;

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'avatar_crop_screen.dart';
import 'group_chat_screen.dart';
import 'sigma_gallery_screen.dart';

/// Telegram-style "New group": name, description, avatar, open/closed toggle
/// and an initial member picker — scoped to people you actually follow, not
/// every user on the platform.
class GroupCreateScreen extends StatefulWidget {
  final Map user;
  const GroupCreateScreen({super.key, required this.user});
  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isOpen = false;
  bool _creating = false;
  Uint8List? _avatarBytes;

  List<Map> _contacts = [];
  bool _loadingUsers = true;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    // "Contacts" = people you follow — same scope Instagram/Telegram use for
    // a new-group invite list, not every account on the platform.
    final following =
        await ApiService.getFollowing(widget.user['id'].toString(), limit: 200);
    if (mounted) {
      setState(() {
        _contacts = following;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => const SigmaGalleryScreen(type: RequestType.image)),
    );
    Uint8List? raw;
    if (picked is Uint8List) {
      raw = picked;
    } else if (picked is List<Uint8List> && picked.isNotEmpty) {
      raw = picked.first; // web: bytes read already, no dart:io File
    } else if (picked is List<File> && picked.isNotEmpty) {
      raw = await picked.first.readAsBytes();
    }
    if (raw == null || !mounted) return;
    final cropSrc = raw;
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AvatarCropScreen(imageBytes: cropSrc)),
    );
    if (cropped == null) return;
    setState(() => _avatarBytes = cropped);
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    String? avatarUrl;
    if (_avatarBytes != null) {
      avatarUrl = await ApiService.uploadMedia(_avatarBytes!,
          folder: 'group',
          ext: 'png',
          contentType: 'image/png',
          userId: widget.user['id'].toString());
    }
    final res = await ApiService.createGroup(name,
        description: _descCtrl.text.trim(), isOpen: _isOpen, avatarUrl: avatarUrl);
    if (res['success'] != true) {
      if (mounted) setState(() => _creating = false);
      return;
    }
    final group = Map<String, dynamic>.from(res['data']);
    // Members added CONCURRENTLY — this used to be one sequential await per
    // member (N round-trips in a row), which is what made creating a group
    // with several people feel slow.
    await Future.wait(_selected
        .map((id) => ApiService.addGroupMember(group['id'].toString(), id)));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => GroupChatScreen(user: widget.user, group: group)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('newGroupTitle'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: c.surface2),
                child: ClipOval(
                  child: _avatarBytes != null
                      ? Image.memory(_avatarBytes!, fit: BoxFit.cover)
                      : Icon(Icons.camera_alt_rounded,
                          color: c.inkSoft, size: 30),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
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
            controller: _descCtrl,
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
          const SizedBox(height: 8),
          SwitchListTile(
            value: _isOpen,
            onChanged: (v) => setState(() => _isOpen = v),
            activeColor: c.accent,
            title: Text(context.t('openGroupLabel'), style: TextStyle(color: c.ink)),
            subtitle: Text(
                _isOpen ? context.t('openGroupHint') : context.t('closedGroupHint'),
                style: TextStyle(color: c.inkSoft, fontSize: 12)),
          ),
          const Divider(height: 28),
          Text(context.t('addMembersLabel'),
              style: TextStyle(
                  color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          if (_loadingUsers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(context.t('noContactsYet'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkSoft, fontSize: 13)),
            )
          else
            ..._contacts.map((u) {
              final id = u['id'].toString();
              final sel = _selected.contains(id);
              return CheckboxListTile(
                value: sel,
                onChanged: (_) => setState(
                    () => sel ? _selected.remove(id) : _selected.add(id)),
                activeColor: c.accent,
                secondary: CircleAvatar(
                  backgroundColor: c.surface2,
                  backgroundImage: u['avatar_url'] != null
                      ? NetworkImage(u['avatar_url'])
                      : null,
                  child: u['avatar_url'] == null
                      ? Icon(Icons.person, color: c.inkSoft)
                      : null,
                ),
                title: Text((u['username'] ?? 'User').toString(),
                    style: TextStyle(color: c.ink)),
              );
            }),
        ],
      ),
      // Fixed at the bottom — always reachable regardless of how long the
      // contact list is, instead of scrolling away as one more list item.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: ListenableBuilder(
        listenable: _nameCtrl,
        builder: (_, __) {
          final ready = _nameCtrl.text.trim().isNotEmpty && !_creating;
          return FloatingActionButton(
            backgroundColor: ready ? c.accent : c.ink.withOpacity(0.2),
            onPressed: ready ? _create : null,
            child: _creating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : const Icon(Icons.check_rounded, color: Colors.white),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }
}
