import 'package:flutter/material.dart';

import '../data/exercises_data.dart';
import '../l10n/app_strings.dart';
import '../theme/brutal_theme.dart';
import 'workout_player_screen.dart';

/// SigmaFit catalogue: pick a timed circuit, get a voice-coached workout.
///
/// Everything (names, technique cues) is bundled in the app as l10n keys —
/// zero server/CDN cost, and the whole catalogue re-translates when the
/// language changes.
class SigmaFitScreen extends StatefulWidget {
  const SigmaFitScreen({super.key});

  @override
  State<SigmaFitScreen> createState() => _SigmaFitScreenState();
}

class _SigmaFitScreenState extends State<SigmaFitScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  /// Hides anything needing dumbbells/barbell/a bar — the common case of
  /// "I'm at home with nothing".
  bool _noEquipOnly = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<FitRoutine> _forTab(FitGender g) => kFitRoutines
      .where((r) => r.matchesGender(g))
      .where((r) => !_noEquipOnly || r.equipment == FitEquipment.none)
      .toList();

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.t('sigmaFitTitle')),
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.ink,
          unselectedLabelColor: c.inkSoft,
          indicatorColor: c.accent,
          indicatorWeight: 2.5,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(text: context.t('fitTabMen')),
            Tab(text: context.t('fitTabWomen')),
          ],
        ),
      ),
      body: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilterChip(
              label: Text(context.t('fitNoEquipOnly')),
              selected: _noEquipOnly,
              onSelected: (v) => setState(() => _noEquipOnly = v),
              showCheckmark: false,
              avatar: Icon(
                  _noEquipOnly
                      ? Icons.check_circle_rounded
                      : Icons.home_rounded,
                  size: 18,
                  color: _noEquipOnly ? c.accent : c.inkSoft),
              backgroundColor: c.surface,
              selectedColor: c.accent.withOpacity(0.16),
              side: BorderSide(
                  color: _noEquipOnly
                      ? c.accent.withOpacity(0.5)
                      : c.ink.withOpacity(0.08)),
              labelStyle: TextStyle(
                  color: c.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _list(c, _forTab(FitGender.male)),
              _list(c, _forTab(FitGender.female)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _list(BrutalColors c, List<FitRoutine> routines) {
    if (routines.isEmpty) {
      return Center(
        child: Text(context.t('fitNothingFound'),
            style: TextStyle(color: c.inkSoft)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: routines.length,
      itemBuilder: (_, i) => _card(c, routines[i]),
    );
  }

  Color _levelColor(BrutalColors c, FitLevel l) {
    switch (l) {
      case FitLevel.beginner:
        return c.accent2;
      case FitLevel.intermediate:
        return c.accent;
      case FitLevel.advanced:
        return c.danger;
    }
  }

  Widget _card(BrutalColors c, FitRoutine r) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WorkoutPlayerScreen(routine: r)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.ink.withOpacity(0.06)),
        ),
        child: Column(children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  c.accent.withOpacity(0.22),
                  c.accent.withOpacity(0.10),
                ]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(r.icon, color: c.accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t(r.titleKey),
                      style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 3),
                  // Counts and duration are computed from the routine, never
                  // stored, so they can't drift out of sync with its content.
                  Text(
                      context
                          .t('fitRoutineSubtitle')
                          .replaceAll('{n}', '${r.exercises.length}')
                          .replaceAll('{min}', '${r.estimatedMinutes}'),
                      style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkSoft),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _chip(c, context.t(r.levelKey), _levelColor(c, r.level)),
            const SizedBox(width: 6),
            if (r.equipment != FitEquipment.none) ...[
              _chip(c, context.t(r.equipmentKey), c.inkSoft),
              const SizedBox(width: 6),
            ],
            if (r.sets > 1) ...[
              _chip(
                  c,
                  context.t('fitSetsLabel').replaceAll('{n}', '${r.sets}'),
                  c.inkSoft),
              const SizedBox(width: 6),
            ],
            _chip(
                c,
                context
                    .t('fitKcalLabel')
                    .replaceAll('{n}', '${r.estimatedKcal}'),
                c.accent3),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(BrutalColors c, String label, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: tint, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}
