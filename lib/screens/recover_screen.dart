import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'main_screen.dart';

/// Reset a forgotten password using the 12-word recovery phrase.
/// No email or phone involved.
class RecoverScreen extends StatefulWidget {
  const RecoverScreen({super.key});
  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _userCtrl = TextEditingController();
  final _phraseCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String _error = '';

  Future<void> _submit() async {
    final username = _userCtrl.text.trim();
    final phrase = _phraseCtrl.text.trim();
    final pass = _passCtrl.text;
    if (username.isEmpty || phrase.isEmpty || pass.isEmpty) {
      setState(() => _error = context.t('fillAll'));
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = context.t('passTooShort'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ApiService.recover(username, phrase, pass);
      if (res['success'] == true) {
        HapticFeedback.lightImpact();
        ApiService.setToken(res['data']['token']);
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (_) => MainScreen(user: res['data']['user'])),
            (r) => false,
          );
        }
      } else {
        setState(() => _error = res['error'] ?? context.t('recoverFailed'));
      }
    } catch (_) {
      setState(() => _error = context.t('connError'));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _phraseCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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
                context.t('recoverTitle'),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('recoverSubtitle'),
                style: TextStyle(color: c.inkSoft, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),

              _label(c, context.t('username')),
              const SizedBox(height: 8),
              _box(
                c,
                TextField(
                  controller: _userCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                    LengthLimitingTextInputFormatter(30),
                  ],
                  style: TextStyle(
                      color: c.ink, fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: _dec(c, context.t('username')),
                ),
              ),
              const SizedBox(height: 18),

              _label(c, context.t('recoveryPhrase')),
              const SizedBox(height: 8),
              _box(
                c,
                TextField(
                  controller: _phraseCtrl,
                  maxLines: 3,
                  minLines: 3,
                  style: TextStyle(
                      color: c.ink, fontSize: 15, height: 1.5),
                  decoration: _dec(c, context.t('phraseHint')),
                ),
              ),
              const SizedBox(height: 18),

              _label(c, context.t('newPassword')),
              const SizedBox(height: 8),
              _box(
                c,
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: TextStyle(
                      color: c.ink, fontSize: 15, fontWeight: FontWeight.w500),
                  decoration: _dec(c, context.t('newPassword')).copyWith(
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: c.inkSoft,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.danger.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline_rounded, color: c.danger, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_error,
                            style: TextStyle(
                                color: c.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.w500))),
                  ]),
                ),
              ],

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: GestureDetector(
                  onTap: _loading ? null : _submit,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: c.buttonGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: _loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: c.onAccent),
                          )
                        : Text(
                            context.t('resetPassword'),
                            style: TextStyle(
                                color: c.onAccent,
                                fontWeight: FontWeight.w700,
                                fontSize: 16),
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

  Widget _label(BrutalColors c, String t) => Text(
        t,
        style: TextStyle(
            color: c.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600),
      );

  Widget _box(BrutalColors c, Widget child) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: c.ink.withOpacity(0.1)),
        ),
        child: child,
      );

  InputDecoration _dec(BrutalColors c, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w400),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}
