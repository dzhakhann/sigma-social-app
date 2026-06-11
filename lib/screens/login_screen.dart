import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool isLoading = false;
  bool _registerMode = false;
  String message = '';

  Future<void> _submit() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
    setState(() {
      isLoading = true;
      message = '';
    });
    try {
      if (_registerMode) {
        final reg = await ApiService.register(emailCtrl.text, passCtrl.text);
        if (reg['success'] != true) {
          setState(() {
            message = '✕ ${reg['error']}';
            isLoading = false;
          });
          return;
        }
      }
      final data = await ApiService.login(emailCtrl.text, passCtrl.text);
      if (data['success'] == true) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => MainScreen(user: data['data']['user'])),
          );
        }
      } else {
        setState(() => message = '✕ ${data['error']}');
      }
    } catch (e) {
      setState(() => message = '✕ $e');
    }
    if (mounted) setState(() => isLoading = false);
  }

  void _setLang(String lang) =>
      appConfig.value = appConfig.value.copyWith(lang: lang);

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final lang = AppScope.of(context).lang;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // language switch
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LangPill('RU', lang == 'ru', () => _setLang('ru')),
                      const SizedBox(width: 6),
                      _LangPill('EN', lang == 'en', () => _setLang('en')),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // wordmark
                Stack(
                  children: [
                    Positioned(
                      left: 0,
                      bottom: 8,
                      child: Container(
                        width: 220,
                        height: 22,
                        color: c.accent,
                      ),
                    ),
                    Text(
                      context.t('appName'),
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        color: c.ink,
                        letterSpacing: -3,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('tagline'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: c.inkSoft,
                      letterSpacing: 1),
                ),
                const SizedBox(height: 40),
                Text(
                  _registerMode
                      ? context.t('joinPulse')
                      : context.t('welcome'),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: c.ink),
                ),
                const SizedBox(height: 16),
                _BrutalField(
                  controller: emailCtrl,
                  hint: context.t('email'),
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                _BrutalField(
                  controller: passCtrl,
                  hint: context.t('password'),
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.danger, width: 2),
                    ),
                    child: Text(message,
                        style: TextStyle(
                            color: c.ink, fontWeight: FontWeight.w700)),
                  ),
                ],
                const SizedBox(height: 24),
                BrutalTap(
                  onTap: isLoading ? null : _submit,
                  fill: c.accent,
                  radius: 14,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shadowOffset: const Offset(5, 5),
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: c.onAccent),
                          )
                        : Text(
                            context.t('enter'),
                            style: TextStyle(
                              color: c.onAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _registerMode = !_registerMode;
                      message = '';
                    }),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _registerMode
                                ? '${context.t('login')} '
                                : '${context.t('newHere')} ',
                            style: TextStyle(color: c.inkSoft, fontSize: 14),
                          ),
                          TextSpan(
                            text: _registerMode
                                ? context.t('login')
                                : context.t('register'),
                            style: TextStyle(
                              color: c.accent2,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }
}

class _LangPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _LangPill(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.ink, width: 2),
          boxShadow: active
              ? [BoxShadow(color: c.shadow, offset: const Offset(2, 2))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: active ? c.onAccent : c.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _BrutalField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  const _BrutalField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.ink, width: 2.5),
        boxShadow: [BoxShadow(color: c.shadow, offset: const Offset(3, 3))],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: TextStyle(
            color: c.ink, fontWeight: FontWeight.w700, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.inkSoft, fontWeight: FontWeight.w600),
          prefixIcon: Icon(icon, color: c.inkSoft, size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        ),
      ),
    );
  }
}
