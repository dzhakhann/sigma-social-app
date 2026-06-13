import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'main_screen.dart';

/// Trust Wallet-style confirmation: the app asks for a few specific positions
/// ("Word #4") and the user picks the correct word from multiple choices.
/// Pure client-side — the phrase is already in memory.
class RecoveryVerifyScreen extends StatefulWidget {
  final Map user;
  final String phrase;
  const RecoveryVerifyScreen(
      {super.key, required this.user, required this.phrase});

  @override
  State<RecoveryVerifyScreen> createState() => _RecoveryVerifyScreenState();
}

class _Question {
  final int position; // 1-based
  final String correct;
  final List<String> options;
  const _Question(this.position, this.correct, this.options);
}

class _RecoveryVerifyScreenState extends State<RecoveryVerifyScreen> {
  static const int _questionCount = 3;
  static const List<String> _fallback = [
    'river', 'stone', 'cloud', 'tiger', 'frost', 'willow', 'ocean', 'ember',
  ];

  late final List<_Question> _questions;
  late final List<String?> _selected;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final words = widget.phrase
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final rnd = Random();

    // pick distinct positions, in ascending order
    final n = min(_questionCount, words.length);
    final positions = <int>{};
    while (positions.length < n) {
      positions.add(rnd.nextInt(words.length));
    }
    final sorted = positions.toList()..sort();

    final distinct = words.toSet().toList();
    _questions = sorted.map((idx) {
      final correct = words[idx];
      // decoys: other distinct phrase words, padded from fallback if needed
      final decoyPool = <String>{...distinct, ..._fallback}..remove(correct);
      final decoys = decoyPool.toList()..shuffle(rnd);
      final options = <String>{correct, ...decoys.take(3)}.toList()
        ..shuffle(rnd);
      return _Question(idx + 1, correct, options);
    }).toList();

    _selected = List<String?>.filled(_questions.length, null);
  }

  bool get _allAnswered => !_selected.contains(null);

  void _pick(int q, String word) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected[q] = word;
      _error = '';
    });
  }

  void _confirm() {
    bool ok = true;
    for (int i = 0; i < _questions.length; i++) {
      if (_selected[i] != _questions[i].correct) ok = false;
    }
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => MainScreen(user: widget.user)),
        (r) => false,
      );
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = context.t('verifyWrong');
        for (int i = 0; i < _selected.length; i++) {
          _selected[i] = null;
        }
      });
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
          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('verifyTitle'),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('verifySubtitle'),
                style: TextStyle(color: c.inkSoft, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),

              for (int q = 0; q < _questions.length; q++) ...[
                _questionBlock(c, q),
                const SizedBox(height: 18),
              ],

              if (_error.isNotEmpty) ...[
                Row(children: [
                  Icon(Icons.error_outline_rounded, color: c.danger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error,
                        style: TextStyle(
                            color: c.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: GestureDetector(
                  onTap: _allAnswered ? _confirm : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _allAnswered ? 1 : 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: c.buttonGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        context.t('verifyConfirm'),
                        style: TextStyle(
                            color: c.onAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionBlock(BrutalColors c, int q) {
    final question = _questions[q];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.ink.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.t('wordLabel')} #${question.position}',
            style: TextStyle(
                color: c.inkSoft, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final opt in question.options)
                _optionChip(c, q, opt, selected: _selected[q] == opt),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionChip(BrutalColors c, int q, String word,
      {required bool selected}) {
    return GestureDetector(
      onTap: () => _pick(q, word),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? c.accent.withOpacity(0.14) : c.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c.accent : c.ink.withOpacity(0.12),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Text(
          word,
          style: TextStyle(
            color: selected ? c.accent : c.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
