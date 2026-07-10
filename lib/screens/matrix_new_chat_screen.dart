import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/matrix_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'matrix_chat_room_screen.dart';

/// Start a new encrypted DM — by Sigma user or raw Matrix ID.
class MatrixNewChatScreen extends StatefulWidget {
  final Map user;
  const MatrixNewChatScreen({super.key, required this.user});

  @override
  State<MatrixNewChatScreen> createState() => _MatrixNewChatScreenState();
}

class _MatrixNewChatScreenState extends State<MatrixNewChatScreen> {
  List _users = [];
  bool _loading = true;
  bool _busy = false;
  final _mxidCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mxidCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await ApiService.getUsers();
    if (mounted) {
      setState(() {
        _users =
            all.where((u) => u['id'] != widget.user['id']).toList();
        _loading = false;
      });
    }
  }

  Future<void> _start(String mxid) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final room = await MatrixService.instance.openDirectChat(mxid);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MatrixChatRoomScreen(room: room, user: widget.user),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('couldNotOpen') + ': $e')),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final matrix = MatrixService.instance;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('newChatTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Direct Matrix ID',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _mxidCtrl,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          hintText: '@user:matrix.org',
                          filled: true,
                          fillColor: c.surface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final mxid = _mxidCtrl.text.trim();
                              if (mxid.startsWith('@')) _start(mxid);
                            },
                      icon: Icon(Icons.arrow_forward_rounded, color: c.accent),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Sigma users (same username on homeserver)',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 8),
                if (_users.isEmpty)
                  Text(context.t('noUsersFound'), style: TextStyle(color: c.inkSoft))
                else
                  ..._users.map((u) {
                    final name = (u['username'] ?? 'user').toString();
                    final mxid = matrix.mxidFromUsername(name);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: c.surface,
                      child: ListTile(
                        title: Text(name),
                        subtitle: Text(mxid, style: TextStyle(color: c.inkSoft)),
                        onTap: _busy ? null : () => _start(mxid),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
