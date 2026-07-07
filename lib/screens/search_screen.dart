import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../widgets/ai_reco_card.dart';
import 'profile_screen.dart';

/// "Рекомендации" — find people, suggested connections (LinkedIn-style),
/// and the profile-exchange entry. No posts here.
class SearchScreen extends StatefulWidget {
  final Map user;
  const SearchScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List _results = [];
  List _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  String get _uid => widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final all = await ApiService.getUsers();
    if (!mounted) return;
    final people = all
        .where((u) =>
            u['id'].toString() != _uid &&
            !(u['email']?.toString() ?? '').endsWith('@bots.local'))
        .toList();
    people.shuffle();
    setState(() => _suggestions = people.take(20).toList());
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _searching = true);
    final data = await ApiService.searchUsers(q);
    if (mounted) {
      setState(() {
        _results = data.where((u) => u['id'].toString() != _uid).toList();
        _searching = false;
      });
    }
  }

  String _name(Map u) {
    final full = [u['first_name'], u['last_name']]
        .where((e) => (e ?? '').toString().trim().isNotEmpty)
        .map((e) => e.toString())
        .join(' ')
        .trim();
    return full.isNotEmpty ? full : (u['username'] ?? 'User').toString();
  }

  void _openProfile(Map u) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
              user: widget.user, targetUserId: u['id'], isOwnProfile: false),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final hasQuery = _ctrl.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Рекомендации')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _ctrl,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: 'Найти людей по имени или @нику…',
              prefixIcon: Icon(Icons.search, color: c.accent),
              suffixIcon: hasQuery
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
          child: _searching
              ? const Center(child: CircularProgressIndicator())
              : hasQuery
                  ? _resultsList(c)
                  : _discover(c),
        ),
      ]),
    );
  }

  Widget _resultsList(BrutalColors c) {
    if (_results.isEmpty) {
      return Center(
          child: Text('Ничего не найдено',
              style: TextStyle(color: c.inkSoft)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _results.length,
      itemBuilder: (_, i) => _personTile(c, _results[i]),
    );
  }

  Widget _discover(BrutalColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        AiRecoCard(user: widget.user),
        // Profile exchange
        GestureDetector(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Скоро: обмен профилями рядом — поднеси телефоны друг к другу (Bluetooth).'))),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [c.accent.withOpacity(0.22), c.accent3.withOpacity(0.12)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.accent.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.wifi_tethering_rounded, color: c.accent, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Обмен профилями',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: c.ink)),
                    Text('Поднеси телефоны — обменяйтесь аккаунтами',
                        style: TextStyle(color: c.inkSoft, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.inkSoft),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Text('Люди, которых стоит добавить',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 15, color: c.ink)),
        const SizedBox(height: 6),
        if (_suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
                child: Text('Пока некого предложить',
                    style: TextStyle(color: c.inkSoft))),
          )
        else
          ..._suggestions.map((u) => _personTile(c, u)),
      ],
    );
  }

  Widget _personTile(BrutalColors c, Map u) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
          color: c.surface, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () => _openProfile(u),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: c.surface2,
          backgroundImage: u['avatar_url'] != null
              ? CachedNetworkImageProvider(u['avatar_url'])
              : null,
          child: u['avatar_url'] == null
              ? Icon(Icons.person, color: c.inkSoft)
              : null,
        ),
        title: Row(children: [
          Flexible(
            child: Text(_name(u),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          if (u['is_verified'] == true) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified_rounded, size: 14, color: c.ink),
          ],
        ]),
        subtitle: Text(
            '@${u['username'] ?? ''}${(u['work'] ?? '').toString().trim().isNotEmpty ? ' · ${u['work']}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
        trailing: Icon(Icons.chevron_right, color: c.inkSoft),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
