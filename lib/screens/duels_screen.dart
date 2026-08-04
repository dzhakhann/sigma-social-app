import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/app_strings.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'goals_screen.dart' show kCats, catOf, catColor;

/// Challenge a friend to a race on the same goal — each side tracks their
/// OWN progress, first to 100% wins. Uses the same categories as GoalsScreen.
class DuelsScreen extends StatefulWidget {
  final Map user;
  const DuelsScreen({super.key, required this.user});
  @override
  State<DuelsScreen> createState() => _DuelsScreenState();
}

class _DuelsScreenState extends State<DuelsScreen> {
  List _duels = [];
  bool _loading = true;
  String get _myId => widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.getDuels();
    if (mounted) setState(() { _duels = data; _loading = false; });
  }

  bool _isChallenger(Map d) => d['challenger_id'].toString() == _myId;
  int _myProgress(Map d) => (_isChallenger(d) ? d['challenger_progress'] : d['opponent_progress']) ?? 0;
  int _theirProgress(Map d) => (_isChallenger(d) ? d['opponent_progress'] : d['challenger_progress']) ?? 0;
  String _theirName(Map d) => (_isChallenger(d) ? d['opponent_username'] : d['challenger_username'] ?? 'User').toString();
  String? _theirAvatar(Map d) => _isChallenger(d) ? d['opponent_avatar'] : d['challenger_avatar'];
  String? _myAvatar(Map d) => _isChallenger(d) ? d['challenger_avatar'] : d['opponent_avatar'];

  List get _pendingForMe => _duels
      .where((d) => d['status'] == 'pending' && d['opponent_id'].toString() == _myId)
      .toList();
  List get _pendingSent => _duels
      .where((d) => d['status'] == 'pending' && d['challenger_id'].toString() == _myId)
      .toList();
  List get _active => _duels.where((d) => d['status'] == 'active').toList();
  List get _finished => _duels
      .where((d) => d['status'] == 'completed' || d['status'] == 'declined')
      .toList();

  Future<void> _bump(Map d) async {
    final next = (_myProgress(d) + 10).clamp(0, 100);
    setState(() {
      if (_isChallenger(d)) {
        d['challenger_progress'] = next;
      } else {
        d['opponent_progress'] = next;
      }
      if (next >= 100) {
        d['status'] = 'completed';
        d['winner_id'] = _myId;
      }
    });
    await ApiService.updateDuelProgress(d['id'].toString(), next);
    if (next >= 100) _celebrate();
  }

  void _celebrate() {
    final c = context.k;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 1300), () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.5, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, v, __) => Transform.scale(
              scale: v,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.emoji_events_rounded, color: c.accent, size: 64),
                  const SizedBox(height: 12),
                  Text(context.t('duelWonMsg'),
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 18)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _respond(Map d, bool accept) async {
    setState(() => d['status'] = accept ? 'active' : 'declined');
    await ApiService.respondDuel(d['id'].toString(), accept);
    _load();
  }

  Future<void> _createDuel() async {
    final ctrl = TextEditingController();
    String cat = 'personal';
    Map? opponent;
    final c = context.k;
    final following = await ApiService.getFollowing(_myId, limit: 200);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 18, right: 18, top: 18,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('newDuelTitle'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: context.t('duelHint')),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: kCats.map((k) {
                  final sel = k.id == cat;
                  final col = catColor(c, k.id);
                  return GestureDetector(
                    onTap: () => setSheet(() => cat = k.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? col.withOpacity(0.18) : c.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? col : Colors.transparent, width: 1.2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(k.icon, size: 16, color: sel ? col : c.inkSoft),
                        const SizedBox(width: 6),
                        Text(ctx.t('cat_${k.id}'),
                            style: TextStyle(
                                color: sel ? c.ink : c.inkSoft,
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(context.t('pickOpponentLabel'),
                  style: TextStyle(color: c.inkSoft, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: following.isEmpty
                    ? Center(
                        child: Text(context.t('noContactsYet'),
                            style: TextStyle(color: c.inkSoft, fontSize: 12)),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: following.length,
                        itemBuilder: (_, i) {
                          final u = following[i];
                          final sel = opponent != null && opponent!['id'].toString() == u['id'].toString();
                          return GestureDetector(
                            onTap: () => setSheet(() => opponent = u),
                            child: Container(
                              width: 64,
                              margin: const EdgeInsets.only(right: 10),
                              child: Column(children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: sel ? c.accent : Colors.transparent, width: 2.4),
                                  ),
                                  child: CircleAvatar(
                                    radius: 26,
                                    backgroundColor: c.surface2,
                                    backgroundImage: (u['avatar_url'] ?? '').toString().isEmpty
                                        ? null
                                        : CachedNetworkImageProvider(u['avatar_url']),
                                    child: (u['avatar_url'] ?? '').toString().isEmpty
                                        ? Icon(Icons.person, color: c.inkSoft)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text((u['username'] ?? '').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: c.inkSoft, fontSize: 11)),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: c.accentFill,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  onPressed: (ctrl.text.trim().isEmpty || opponent == null)
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await ApiService.createDuel(ctrl.text.trim(), cat, opponent!['id'].toString());
                          _load();
                        },
                  child: Text(context.t('sendChallengeBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('duelsTitle'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.accentFill,
        onPressed: _createDuel,
        icon: const Icon(Icons.add),
        label: Text(context.t('newDuelBtn')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                children: [
                  if (_duels.isEmpty) _empty(c),
                  if (_pendingForMe.isNotEmpty) ...[
                    _sectionTitle(c, context.t('duelInvitesLabel')),
                    ..._pendingForMe.map((d) => _inviteCard(c, d)),
                  ],
                  if (_active.isNotEmpty) ...[
                    _sectionTitle(c, context.t('activeDuelsLabel')),
                    ..._active.map((d) => _duelCard(c, d)),
                  ],
                  if (_pendingSent.isNotEmpty) ...[
                    _sectionTitle(c, context.t('duelsWaitingLabel')),
                    ..._pendingSent.map((d) => _waitingCard(c, d)),
                  ],
                  if (_finished.isNotEmpty) ...[
                    _sectionTitle(c, context.t('duelsHistoryLabel')),
                    ..._finished.map((d) => _duelCard(c, d, faded: true)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _empty(BrutalColors c) => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(children: [
          Icon(Icons.sports_kabaddi_rounded, size: 54, color: c.inkSoft),
          const SizedBox(height: 12),
          Text(context.t('noDuelsYet'),
              style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(context.t('noDuelsYetHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.4)),
        ]),
      );

  Widget _sectionTitle(BrutalColors c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(t, style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w700, fontSize: 13)),
      );

  Widget _avatarOf(BrutalColors c, String? url, {double r = 18}) => CircleAvatar(
        radius: r,
        backgroundColor: c.surface2,
        backgroundImage: (url ?? '').isEmpty ? null : CachedNetworkImageProvider(url!),
        child: (url ?? '').isEmpty ? Icon(Icons.person, color: c.inkSoft, size: r) : null,
      );

  Widget _inviteCard(BrutalColors c, Map d) {
    final cat = catOf(d['category']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accent.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _avatarOf(c, d['challenger_avatar']),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(style: TextStyle(color: c.ink, fontSize: 14), children: [
                TextSpan(
                    text: '${d['challenger_username']} ',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: context.t('challengesYouLabel')),
              ]),
            ),
          ),
          Icon(cat.icon, size: 18, color: catColor(c, cat.id)),
        ]),
        const SizedBox(height: 8),
        Text('"${d['title']}"',
            style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _respond(d, false),
              style: OutlinedButton.styleFrom(foregroundColor: c.inkSoft),
              child: Text(context.t('declineBtn')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => _respond(d, true),
              style: FilledButton.styleFrom(backgroundColor: c.accentFill),
              child: Text(context.t('acceptBtn')),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _waitingCard(BrutalColors c, Map d) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: c.surface, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.ink.withOpacity(0.06))),
        child: Row(children: [
          _avatarOf(c, d['opponent_avatar']),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('"${d['title']}"',
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
              Text(context.t('waitingForLabel').replaceAll('{u}', '${d['opponent_username']}'),
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
            ]),
          ),
          Icon(Icons.hourglass_empty_rounded, color: c.inkSoft, size: 18),
        ]),
      );

  Widget _duelCard(BrutalColors c, Map d, {bool faded = false}) {
    final cat = catOf(d['category']);
    final mine = _myProgress(d);
    final theirs = _theirProgress(d);
    final iWon = d['status'] == 'completed' && d['winner_id'].toString() == _myId;
    final theyWon = d['status'] == 'completed' && d['winner_id'].toString() != _myId && d['winner_id'] != null;
    return Opacity(
      opacity: faded ? 0.75 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.ink.withOpacity(0.06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(cat.icon, size: 16, color: catColor(c, cat.id)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('"${d['title']}"',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            if (iWon) Icon(Icons.emoji_events_rounded, color: c.accent, size: 18),
            if (theyWon) Icon(Icons.emoji_events_outlined, color: c.inkSoft, size: 18),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _sideBar(c, _myAvatar(d), context.t('youLabel'), mine, c.accent)),
            const SizedBox(width: 10),
            Text('VS', style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w800, fontSize: 11)),
            const SizedBox(width: 10),
            Expanded(child: _sideBar(c, _theirAvatar(d), _theirName(d), theirs, c.accent3)),
          ]),
          if (d['status'] == 'active') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _bump(d),
                style: OutlinedButton.styleFrom(foregroundColor: c.accent, side: BorderSide(color: c.accent)),
                child: Text(context.t('plus10')),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _sideBar(BrutalColors c, String? avatar, String name, int progress, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _avatarOf(c, avatar, r: 12),
        const SizedBox(width: 6),
        Expanded(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: progress / 100,
          minHeight: 8,
          backgroundColor: c.surface2,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
      const SizedBox(height: 3),
      Text('$progress%', style: TextStyle(color: c.inkSoft, fontSize: 11)),
    ]);
  }
}
