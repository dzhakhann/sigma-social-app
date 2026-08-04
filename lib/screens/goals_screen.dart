import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'year_review_screen.dart';
import 'duels_screen.dart';

// Goal categories: id → (icon, color-picker).
//
// The display name is NOT stored here — it's looked up as `cat_<id>` at render
// time so switching language re-translates it. A hardcoded Russian `label`
// field used to sit alongside; nothing read it, and keeping it invited someone
// to render it and quietly break localization.
class GoalCat {
  final String id;
  final IconData icon;
  const GoalCat(this.id, this.icon);
}

const List<GoalCat> kCats = [
  GoalCat('study', Icons.school_outlined),
  GoalCat('career', Icons.work_outline_rounded),
  GoalCat('health', Icons.favorite_outline_rounded),
  GoalCat('finance', Icons.savings_outlined),
  GoalCat('relationships', Icons.people_outline_rounded),
  GoalCat('hobby', Icons.brush_outlined),
  GoalCat('personal', Icons.star_outline_rounded),
  GoalCat('other', Icons.category_outlined),
];

GoalCat catOf(String? id) =>
    kCats.firstWhere((c) => c.id == id, orElse: () => kCats.last);

Color catColor(BrutalColors c, String id) {
  switch (id) {
    case 'career':
      return c.accent;
    case 'study':
      return c.accent2;
    case 'health':
      return c.danger;
    case 'finance':
      return c.accent3;
    case 'relationships':
      return c.danger;
    case 'hobby':
      return c.accent3;
    default:
      return c.inkSoft;
  }
}

class GoalsScreen extends StatefulWidget {
  final Map user;
  const GoalsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final int year = DateTime.now().year;
  List _goals = [];
  bool _loading = true;
  String _filter = 'all'; // all | active | done | paused

  String get _uid => widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.getGoals(_uid, year: year);
    if (mounted) setState(() { _goals = data; _loading = false; });
  }

  List get _visibleGoals {
    switch (_filter) {
      case 'active':
        return _goals
            .where((g) => g['status'] != 'done' && g['status'] != 'paused')
            .toList();
      case 'done':
        return _goals.where((g) => g['status'] == 'done').toList();
      case 'paused':
        return _goals.where((g) => g['status'] == 'paused').toList();
      default:
        return _goals;
    }
  }

  // One-tap +10% straight from the card (no need to open the sheet).
  Future<void> _bumpProgress(Map g) async {
    HapticFeedback.selectionClick();
    final next = (((g['progress'] ?? 0) as int) + 10).clamp(0, 100);
    setState(() => g['progress'] = next); // optimistic
    if (next >= 100) {
      await ApiService.updateGoal(
          g['id'].toString(), {'progress': 100, 'status': 'done'});
      await _load();
      _celebrate();
    } else {
      await ApiService.updateGoal(g['id'].toString(), {'progress': next});
    }
  }

  int get _done => _goals.where((g) => g['status'] == 'done').length;
  int get _avg => _goals.isEmpty
      ? 0
      : (_goals.fold<int>(0, (s, g) => s + ((g['progress'] ?? 0) as int)) /
              _goals.length)
          .round();

  // ─── Add / edit sheets ─────────────────────────────────────────────────────
  Future<void> _addGoal() async {
    final ctrl = TextEditingController();
    String cat = 'personal';
    final c = context.k;
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
              Text(context.t('newGoalYear').replaceAll('{year}', '$year'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: context.t('goalHint')),
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
                        border: Border.all(
                            color: sel ? col : Colors.transparent, width: 1.2),
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
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: c.accentFill,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: () async {
                    if (ctrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    await ApiService.createGoal(ctrl.text.trim(), cat, year);
                    _load();
                  },
                  child: Text(context.t('addGoalBtn'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editGoal(Map g) async {
    double prog = ((g['progress'] ?? 0) as int).toDouble();
    final c = context.k;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g['title'] ?? '',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(context.t('progressLbl').replaceAll('{n}', '${prog.round()}'),
                  style: TextStyle(color: c.inkSoft)),
              Slider(
                value: prog, min: 0, max: 100, divisions: 20,
                activeColor: c.accent,
                label: '${prog.round()}%',
                onChanged: (v) => setSheet(() => prog = v),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accentFill,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ApiService.updateGoal(
                          g['id'].toString(), {'progress': prog.round()});
                      _load();
                    },
                    child: Text(context.t('saveBtn')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: c.accent2,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: c.accent2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ApiService.updateGoal(
                          g['id'].toString(), {'status': 'done'});
                      await _load();
                      _celebrate();
                    },
                    child: Text(context.t('goalDoneBtn')),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ApiService.updateGoal(
                          g['id'].toString(), {'status': 'paused'});
                      _load();
                    },
                    icon: Icon(Icons.pause_circle_outline,
                        color: c.inkSoft, size: 20),
                    label: Text(context.t('postponeBtn'), style: TextStyle(color: c.inkSoft)),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ApiService.deleteGoal(g['id'].toString());
                      _load();
                    },
                    icon: Icon(Icons.delete_outline, color: c.danger, size: 20),
                    label: Text(context.t('deleteBtn'), style: TextStyle(color: c.danger)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _celebrate() {
    HapticFeedback.mediumImpact();
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
                decoration: BoxDecoration(
                    color: c.surface, borderRadius: BorderRadius.circular(24)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded, color: c.accent2, size: 64),
                  const SizedBox(height: 12),
                  Text(context.t('goalCompletedMsg'),
                      style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 18)),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('myGoalsTitle').replaceAll('{year}', '$year')),
        actions: [
          IconButton(
            tooltip: context.t('duelsTitle'),
            icon: Icon(Icons.sports_kabaddi_rounded, color: c.accent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DuelsScreen(user: widget.user)),
            ),
          ),
          IconButton(
            tooltip: context.t('myYearTooltip'),
            icon: Icon(Icons.auto_awesome_rounded, color: c.accent),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => YearReviewScreen(user: widget.user, year: year)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.accentFill,
        onPressed: _addGoal,
        icon: const Icon(Icons.add),
        label: Text(context.t('goalFabBtn')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                children: [
                  _header(c),
                  const SizedBox(height: 12),
                  if (_goals.isNotEmpty) ...[
                    _filterChips(c),
                    const SizedBox(height: 12),
                  ],
                  if (_goals.isEmpty)
                    _empty(c)
                  else
                    ..._visibleGoals.map((g) => _goalCard(c, g)),
                ],
              ),
            ),
    );
  }

  Widget _filterChips(BrutalColors c) {
    final filters = [
      ['all', context.t('fAll')],
      ['active', context.t('fActive')],
      ['done', context.t('fDone')],
      ['paused', context.t('fPaused')],
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.map((f) {
          final sel = _filter == f[0];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f[0]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: sel ? c.accent : c.ink.withOpacity(0.08)),
                ),
                child: Text(f[1],
                    style: TextStyle(
                        color: sel ? c.onAccent : c.inkSoft,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _header(BrutalColors c) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c.accent.withOpacity(0.22), c.accent3.withOpacity(0.12)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.accent.withOpacity(0.25)),
      ),
      child: Row(children: [
        SizedBox(
          width: 64, height: 64,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _avg / 100),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 64, height: 64,
                child: CircularProgressIndicator(
                  value: v,
                  strokeWidth: 6,
                  backgroundColor: c.surface2,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
              Text('${(v * 100).round()}%',
                  style:
                      const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('myYearHeader').replaceAll('{year}', '$year'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(context.t('doneOfGoals').replaceAll('{done}', '$_done').replaceAll('{total}', '${_goals.length}'),
                  style: TextStyle(color: c.inkSoft, fontSize: 13)),
              const SizedBox(height: 4),
              Text(_motivation(),
                  style: TextStyle(
                      color: c.accent2,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ]),
    );
  }

  String _motivation() {
    if (_goals.isEmpty) return context.t('motivStart');
    if (_avg >= 80) return context.t('motivHigh');
    if (_avg >= 50) return context.t('motivMid');
    if (_avg >= 20) return context.t('motivLow');
    return context.t('motivStep');
  }

  Widget _empty(BrutalColors c) => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(children: [
          Icon(Icons.flag_outlined, size: 54, color: c.inkSoft),
          const SizedBox(height: 12),
          Text(context.t('noGoalsYear').replaceAll('{year}', '$year'),
              style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(context.t('noGoalsYearHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.4)),
        ]),
      );

  Widget _goalCard(BrutalColors c, Map g) {
    final cat = catOf(g['category']);
    final col = catColor(c, cat.id);
    final prog = (g['progress'] ?? 0) as int;
    final done = g['status'] == 'done';
    final paused = g['status'] == 'paused';
    return GestureDetector(
      onTap: () => _editGoal(g),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.ink.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: col.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(cat.icon, size: 18, color: col),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(g['title'] ?? '',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? c.inkSoft : c.ink)),
              ),
              if (done)
                Icon(Icons.check_circle_rounded, color: c.accent2, size: 22)
              else if (paused)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.pause_circle_outline, color: c.inkSoft, size: 18),
                  const SizedBox(width: 4),
                  Text(context.t('postponedLabel'),
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ])
              else ...[
                Text('$prog%',
                    style: TextStyle(
                        color: c.inkSoft, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _bumpProgress(g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(context.t('plus10'),
                        style: TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: prog / 100),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 7,
                  backgroundColor: c.surface2,
                  valueColor: AlwaysStoppedAnimation(done ? c.accent2 : col),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
