import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'recovery_verify_screen.dart';

/// Shown exactly once, right after registration. Displays the 12-word recovery
/// phrase the server generated. The user must save it — it's the only way to
/// recover the account without email or phone.
class RecoveryPhraseScreen extends StatefulWidget {
  final Map user;
  final String phrase;
  const RecoveryPhraseScreen(
      {super.key, required this.user, required this.phrase});

  @override
  State<RecoveryPhraseScreen> createState() => _RecoveryPhraseScreenState();
}

class _RecoveryPhraseScreenState extends State<RecoveryPhraseScreen> {
  bool _saved = false;
  bool _copied = false;

  List<String> get _words =>
      widget.phrase.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.phrase.trim()));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
  }

  void _continue() {
    // Go to the wallet-style confirmation step before entering the app.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RecoveryVerifyScreen(user: widget.user, phrase: widget.phrase),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final words = _words;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.vpn_key_rounded, color: c.accent, size: 26),
              ),
              const SizedBox(height: 20),
              Text(
                context.t('recoveryTitle'),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('recoverySubtitle'),
                style: TextStyle(color: c.inkSoft, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),

              // warning
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.danger.withOpacity(0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: c.danger, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.t('recoveryWarning'),
                        style: TextStyle(
                            color: c.ink, fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // words grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: words.length,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.6,
                ),
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.ink.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}',
                        style: TextStyle(
                            color: c.inkSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          words[i],
                          style: TextStyle(
                              color: c.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // copy
              GestureDetector(
                onTap: _copy,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          _copied
                              ? Icons.check_rounded
                              : Icons.copy_rounded,
                          color: _copied ? c.accent2 : c.ink,
                          size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _copied ? context.t('copied') : context.t('copyPhrase'),
                        style: TextStyle(
                            color: _copied ? c.accent2 : c.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // confirm checkbox
              GestureDetector(
                onTap: () => setState(() => _saved = !_saved),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _saved ? c.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                            color: _saved ? c.accent : c.inkSoft, width: 2),
                      ),
                      child: _saved
                          ? Icon(Icons.check_rounded,
                              size: 16, color: c.onAccent)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.t('savedConfirm'),
                        style: TextStyle(
                            color: c.ink, fontSize: 13.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // continue
              SizedBox(
                width: double.infinity,
                height: 54,
                child: GestureDetector(
                  onTap: _saved ? _continue : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _saved ? 1 : 0.4,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: c.buttonGradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        context.t('continueBtn'),
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
}
