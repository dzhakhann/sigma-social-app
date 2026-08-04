import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/exercises_data.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/exercise_motion.dart';

/// A timed circuit player — on-device TTS calls out each exercise and cue,
/// no video/audio assets needed. Big circular countdown, Apple-Watch-ish.
class WorkoutPlayerScreen extends StatefulWidget {
  final FitRoutine routine;
  const WorkoutPlayerScreen({super.key, required this.routine});
  @override
  State<WorkoutPlayerScreen> createState() => _WorkoutPlayerScreenState();
}

class _WorkoutPlayerScreenState extends State<WorkoutPlayerScreen> {
  final _tts = FlutterTts();
  Timer? _timer;
  int _exerciseIdx = 0;
  bool _resting = false;
  int _remaining = 0;
  bool _paused = false;
  bool _done = false;
  int _elapsedSec = 0;

  /// Which round of the circuit we're on (0-based). A routine's advertised
  /// duration and calories are computed from `sets`, so the player has to
  /// actually run the circuit that many times or the card would be lying.
  int _setIdx = 0;

  FitExercise get _current => widget.routine.exercises[_exerciseIdx];
  bool get _lastExercise =>
      _exerciseIdx == widget.routine.exercises.length - 1;
  bool get _lastSet => _setIdx == widget.routine.sets - 1;
  bool get _isLast => _lastExercise && _lastSet;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage(appConfig.value.lang == 'ru' ? 'ru-RU' : 'en-US');
    _tts.setSpeechRate(0.48);
    _remaining = widget.routine.workSec;
    _announceExercise();
    _startTicker();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _done) return;
      setState(() {
        _elapsedSec++;
        _remaining--;
        if (_remaining == 3 && !_resting) _tts.speak('3, 2, 1');
        if (_remaining <= 0) _advance();
      });
    });
  }

  void _announceExercise() {
    _tts.speak(
        '${context.t(_current.nameKey)}. ${context.t(_current.cueKey)}. ${context.t('beginLabel')}');
  }

  void _advance() {
    if (!_resting) {
      // Work phase finished.
      if (_isLast) {
        _finish();
        return;
      }
      _resting = true;
      _remaining = widget.routine.restSec;
      _tts.speak(context.t('restLabel'));
    } else {
      // Rest finished → next exercise, or back to the top for the next set.
      _resting = false;
      if (_lastExercise) {
        _setIdx++;
        _exerciseIdx = 0;
        _tts.speak(context
            .t('fitSetsLabel')
            .replaceAll('{n}', '${_setIdx + 1}'));
      } else {
        _exerciseIdx++;
      }
      _remaining = widget.routine.workSec;
      _announceExercise();
    }
  }

  void _skip() {
    HapticFeedback.mediumImpact();
    setState(() {
      _remaining = 0;
      _advance();
    });
  }

  Future<void> _finish() async {
    setState(() => _done = true);
    _timer?.cancel();
    _tts.speak(context.t('workoutDoneLabel'));
    await ApiService.logWorkout(widget.routine.id, _elapsedSec);
  }

  Future<void> _confirmExit() async {
    final c = context.k;
    if (_elapsedSec < 20) {
      Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('endWorkoutTitle')),
        content: Text(context.t('endWorkoutHint')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.t('cancelBtn'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.t('endBtn'))),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final totalPhaseSec = _resting ? widget.routine.restSec : widget.routine.workSec;
    final progress = totalPhaseSec == 0 ? 0.0 : 1 - (_remaining / totalPhaseSec);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        leading: IconButton(icon: Icon(Icons.close, color: c.ink), onPressed: _confirmExit),
        title: Text(context.t(widget.routine.titleKey)),
      ),
      body: _done ? _doneView(c) : _playerView(c, progress),
    );
  }

  Widget _playerView(BrutalColors c, double progress) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${_exerciseIdx + 1} / ${widget.routine.exercises.length}',
                style: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w700)),
            // Only worth showing when there's more than one round to track.
            if (widget.routine.sets > 1) ...[
              Text('  ·  ', style: TextStyle(color: c.inkSoft)),
              Text('${_setIdx + 1} / ${widget.routine.sets}',
                  style: TextStyle(
                      color: c.accent, fontWeight: FontWeight.w700)),
            ],
          ]),
          const Spacer(),
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 260, height: 260,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 12,
                  backgroundColor: c.surface2,
                  valueColor: AlwaysStoppedAnimation(_resting ? c.accent3 : c.accent),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _resting
                    ? Icon(Icons.self_improvement_rounded, size: 40, color: c.accent3)
                    : ExerciseMotionAnim(
                        key: ValueKey(_current.id),
                        motion: _current.motion,
                        icon: _current.icon,
                        color: c.accent,
                      ),
                const SizedBox(height: 10),
                Text('$_remaining',
                    style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: c.ink)),
              ]),
            ]),
          ),
          const SizedBox(height: 28),
          Text(_resting ? context.t('restLabel') : context.t(_current.nameKey),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 22)),
          if (!_resting) ...[
            const SizedBox(height: 8),
            Text(context.t(_current.cueKey),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkSoft, fontSize: 14)),
          ],
          const Spacer(),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _skip,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(context.t('skipBtn')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => setState(() => _paused = !_paused),
                style: FilledButton.styleFrom(
                    backgroundColor: c.accentFill, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _doneView(BrutalColors c) {
    final mins = (_elapsedSec / 60).ceil();
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.emoji_events_rounded, color: c.accent, size: 72),
        const SizedBox(height: 16),
        Text(context.t('workoutDoneLabel'),
            style: TextStyle(color: c.ink, fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 6),
        Text(context.t('workoutMinutesLabel').replaceAll('{n}', '$mins'),
            style: TextStyle(color: c.inkSoft, fontSize: 14)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(backgroundColor: c.accentFill, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
          child: Text(context.t('doneBtn')),
        ),
      ]),
    );
  }
}
