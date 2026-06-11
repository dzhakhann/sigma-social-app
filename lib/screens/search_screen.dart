import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  final Map user;
  const SearchScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  void _onSearch(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _isLoading = true);
    final data = await ApiService.searchUsers(query);
    if (mounted) {
      setState(() {
        _results = data.where((u) => u['id'] != widget.user['id']).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: TextField(
            controller: _ctrl,
            autofocus: false,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: Icon(Icons.search, color: c.accent),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _results = []);
                      })
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? Center(
                      child: Text(
                          _ctrl.text.isEmpty
                              ? 'Search for users by username'
                              : 'No results found',
                          style: TextStyle(color: c.inkSoft)))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final u = _results[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          child: ListTile(
                            leading: u['avatar_url'] != null
                                ? CircleAvatar(
                                    backgroundImage:
                                        CachedNetworkImageProvider(
                                            u['avatar_url']))
                                : CircleAvatar(
                                    backgroundColor: c.accent,
                                    child: Icon(Icons.person,
                                        color: c.ink)),
                            title: Text(u['username'] ?? 'User',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(u['bio'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.inkSoft)),
                            trailing: Text(
                                '${u['followers_count'] ?? 0} followers',
                                style: TextStyle(
                                    color: c.inkSoft, fontSize: 12)),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => ProfileScreen(
                                          user: widget.user,
                                          targetUserId: u['id'],
                                          isOwnProfile: false,
                                        ))),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
