import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

class AdminScreen extends StatefulWidget {
  final Map user;
  const AdminScreen({super.key, required this.user});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map _stats = {};
  List _users = [];
  List _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ApiService.adminStats(),
      ApiService.adminUsers(),
      ApiService.adminPosts(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = (results[0] as Map)['data'] ?? {};
      _users = results[1] as List;
      _posts = results[2] as List;
      _loading = false;
    });
  }

  Future<bool> _confirm(String text) async {
    final c = context.k;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: c.surface,
            title: Text('Are you sure?', style: TextStyle(color: c.ink)),
            content: Text(text, style: TextStyle(color: c.inkSoft)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: c.inkSoft))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Yes', style: TextStyle(color: c.danger))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteUser(Map u) async {
    if (!await _confirm('Delete user @${u['username']} and all their content?')) {
      return;
    }
    final r = await ApiService.adminDeleteUser(u['id'].toString());
    if (r['success'] == true) {
      setState(() => _users.remove(u));
    } else {
      _toast(r['error']?.toString() ?? 'Failed');
    }
  }

  Future<void> _toggleAdmin(Map u) async {
    final r = await ApiService.adminToggleAdmin(u['id'].toString());
    if (r['success'] == true) {
      setState(() => u['is_admin'] = r['is_admin']);
    }
  }

  Future<void> _deletePost(Map p) async {
    if (!await _confirm('Delete this post?')) return;
    final r = await ApiService.adminDeletePost(p['id'].toString());
    if (r['success'] == true) {
      setState(() => _posts.remove(p));
    } else {
      _toast(r['error']?.toString() ?? 'Failed');
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: const Text('Admin panel'),
          actions: [
            IconButton(
                onPressed: _loadAll,
                icon: Icon(Icons.refresh_rounded, color: c.ink)),
          ],
          bottom: TabBar(
            labelColor: c.accent,
            unselectedLabelColor: c.inkSoft,
            indicatorColor: c.accent,
            tabs: const [Tab(text: 'Users'), Tab(text: 'Posts')],
          ),
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: c.accent))
            : Column(
                children: [
                  _statsRow(c),
                  Expanded(
                    child: TabBarView(
                      children: [_usersTab(c), _postsTab(c)],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _statsRow(BrutalColors c) {
    final items = [
      ['Users', _stats['users']],
      ['Posts', _stats['posts']],
      ['Comments', _stats['comments']],
      ['Messages', _stats['messages']],
    ];
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${it[1] ?? 0}',
                        style: TextStyle(
                            color: c.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    Text(it[0] as String,
                        style: TextStyle(color: c.inkSoft, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _usersTab(BrutalColors c) {
    if (_users.isEmpty) {
      return Center(
          child: Text('No users', style: TextStyle(color: c.inkSoft)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _users.length,
      itemBuilder: (_, i) {
        final u = _users[i];
        final isAdmin = u['is_admin'] == true;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text('@${u['username'] ?? '?'}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.ink, fontWeight: FontWeight.w700)),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: c.accent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('admin',
                              style:
                                  TextStyle(color: c.accent, fontSize: 10)),
                        ),
                      ],
                    ]),
                    Text('${u['email'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: isAdmin ? 'Remove admin' : 'Make admin',
                onPressed: () => _toggleAdmin(u),
                icon: Icon(
                    isAdmin
                        ? Icons.shield_rounded
                        : Icons.shield_outlined,
                    color: isAdmin ? c.accent : c.inkSoft,
                    size: 20),
              ),
              IconButton(
                onPressed: () => _deleteUser(u),
                icon: Icon(Icons.delete_outline_rounded,
                    color: c.danger, size: 20),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _postsTab(BrutalColors c) {
    if (_posts.isEmpty) {
      return Center(
          child: Text('No posts', style: TextStyle(color: c.inkSoft)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _posts.length,
      itemBuilder: (_, i) {
        final p = _posts[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${p['username'] ?? '?'}',
                        style: TextStyle(
                            color: c.inkSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      (p['content'] ?? '').toString().isEmpty
                          ? '[no text]'
                          : p['content'].toString(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink, fontSize: 14),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deletePost(p),
                icon: Icon(Icons.delete_outline_rounded,
                    color: c.danger, size: 20),
              ),
            ],
          ),
        );
      },
    );
  }
}
