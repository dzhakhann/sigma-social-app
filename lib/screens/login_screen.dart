import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/session.dart';
import '../theme/brutal_theme.dart';
import 'main_screen.dart';
import 'recovery_phrase_screen.dart';
import 'recover_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController(); // confirm password (register only)
  bool _isLoading = false;
  bool _registerMode = false;
  bool _obscurePass = true;
  String _error = '';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    _fadeCtrl.reverse().then((_) {
      setState(() {
        _registerMode = !_registerMode;
        _error = '';
        _pass2Ctrl.clear();
      });
      _fadeCtrl.forward();
    });
  }

  Future<void> _submit() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Fill in all fields');
      return;
    }

    if (_registerMode) {
      if (_passCtrl.text != _pass2Ctrl.text) {
        setState(() => _error = 'Passwords do not match');
        return;
      }
      if (password.length < 6) {
        setState(() => _error = 'Password must be at least 6 characters');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      String? recoveryPhrase;
      if (_registerMode) {
        final reg = await ApiService.register(username, password);
        if (reg['success'] != true) {
          setState(() {
            _error = reg['error'] ?? 'Registration failed';
            _isLoading = false;
          });
          return;
        }
        recoveryPhrase = reg['data']?['recovery_phrase'] as String?;
      }
      final data = await ApiService.login(username, password);
      if (data['success'] == true) {
        HapticFeedback.lightImpact();
        final user = data['data']['user'];
        await Session.save(data['data']['token'], user);
        if (mounted) {
          if (recoveryPhrase != null && recoveryPhrase.isNotEmpty) {
            // First time: show the one-time recovery phrase before entering.
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RecoveryPhraseScreen(user: user, phrase: recoveryPhrase!),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => MainScreen(user: user),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          }
        }
      } else {
        setState(() => _error = data['error'] ?? 'Login failed');
      }
    } catch (e) {
      setState(() => _error = 'Connection error');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 28,
              vertical: size.height * 0.06,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: size.height * 0.88),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Logo ──────────────────────────────────────────────
                  _SigmaLogo(c: c),
                  const SizedBox(height: 48),

                  // ── Heading ───────────────────────────────────────────
                  Text(
                    _registerMode ? 'Create account' : 'Welcome back',
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _registerMode
                        ? 'No email. No phone. Just a username.'
                        : 'Sign in with your username',
                    style:
                        TextStyle(color: c.inkSoft, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 32),

                  // ── Username field ─────────────────────────────────────
                  _Field(
                    controller: _userCtrl,
                    hint: 'Username',
                    icon: Icons.alternate_email_rounded,
                    c: c,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_.]')),
                      LengthLimitingTextInputFormatter(30),
                    ],
                    keyboardType: TextInputType.visiblePassword,
                    textCapitalization: TextCapitalization.none,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 14),

                  // ── Password field ─────────────────────────────────────
                  _Field(
                    controller: _passCtrl,
                    hint: 'Password',
                    icon: Icons.lock_outline_rounded,
                    c: c,
                    obscure: _obscurePass,
                    suffixIcon: GestureDetector(
                      onTap: () =>
                          setState(() => _obscurePass = !_obscurePass),
                      child: Icon(
                        _obscurePass
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: c.inkSoft,
                        size: 20,
                      ),
                    ),
                    onSubmitted: _registerMode ? null : (_) => _submit(),
                  ),

                  // ── Confirm password (register only) ──────────────────
                  if (_registerMode) ...[
                    const SizedBox(height: 14),
                    _Field(
                      controller: _pass2Ctrl,
                      hint: 'Confirm password',
                      icon: Icons.lock_outline_rounded,
                      c: c,
                      obscure: true,
                      onSubmitted: (_) => _submit(),
                    ),
                  ],

                  // ── Privacy note (register only) ──────────────────────
                  if (_registerMode) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: c.accent.withOpacity(0.2), width: 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.shield_outlined,
                            color: c.accent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'We don\'t collect your personal data. No email, no phone — your identity is just your username.',
                            style: TextStyle(
                                color: c.inkSoft, fontSize: 12, height: 1.5),
                          ),
                        ),
                      ]),
                    ),
                  ],

                  // ── Error message ─────────────────────────────────────
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: c.danger.withOpacity(0.4), width: 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded,
                            color: c.danger, size: 18),
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

                  // ── Submit button ─────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: GestureDetector(
                      onTap: _isLoading ? null : _submit,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          gradient: c.buttonGradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: c.accent.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isLoading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: c.onAccent),
                                )
                              : Text(
                                  _registerMode ? 'Create account' : 'Sign in',
                                  style: TextStyle(
                                    color: c.onAccent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Recover account (sign-in only) ────────────────────
                  if (!_registerMode)
                    Center(
                      child: GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const RecoverScreen()),
                                ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'Forgot password?',
                            style: TextStyle(
                                color: c.inkSoft,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),

                  // ── Toggle mode ───────────────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: _isLoading ? null : _toggleMode,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: _registerMode
                                  ? 'Already have an account? '
                                  : 'New here? ',
                              style: TextStyle(
                                  color: c.inkSoft, fontSize: 14),
                            ),
                            TextSpan(
                              text: _registerMode ? 'Sign in' : 'Create account',
                              style: TextStyle(
                                color: c.accent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Logo widget ───────────────────────────────────────────────────────────────
class _SigmaLogo extends StatelessWidget {
  final BrutalColors c;
  const _SigmaLogo({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: c.buttonGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Σ',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SIGMA',
            style: TextStyle(
              color: c.ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1,
            )),
        Text('SOCIAL',
            style: TextStyle(
              color: c.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            )),
      ]),
    ]);
  }
}

// ── Input field ───────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final BrutalColors c;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.c,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.ink.withOpacity(0.1), width: 1),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        onSubmitted: onSubmitted,
        style: TextStyle(
            color: c.ink, fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: c.inkSoft, fontWeight: FontWeight.w400),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(icon, color: c.inkSoft, size: 20),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: suffixIcon,
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 0, vertical: 16),
        ),
      ),
    );
  }
}
