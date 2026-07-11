import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/session.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'pro_screen.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Map user;
  const SettingsScreen({super.key, required this.user});

  static const String _privacyUrl = 'https://sigmacta.pages.dev/privacy';
  static const String _termsUrl = 'https://sigmacta.pages.dev/terms';
  static const String _version = '1.0.0';

  void _setLang(String l) =>
      appConfig.value = appConfig.value.copyWith(lang: l);

  void _setTheme(int i) =>
      appConfig.value = appConfig.value.copyWith(themeIndex: i);

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    await Session.clear();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // Google Play requires an in-app account deletion flow.
  Future<void> _deleteAccount(BuildContext context) async {
    final c = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(context.t('deleteAccount'),
            style: TextStyle(color: c.danger)),
        content: Text(context.t('deleteAccountWarn'),
            style: TextStyle(color: c.inkSoft, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.t('cancelBtn'),
                  style: TextStyle(color: c.inkSoft))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.t('deleteAccountConfirm'),
                  style: TextStyle(
                      color: c.danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final r = await ApiService.deleteAccount();
    if (!context.mounted) return;
    if (r['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('accountDeleted'))));
      await _logout(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((r['error'] ?? context.t('connError')).toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final config = AppScope.of(context).config;
    final lang = config.lang;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Sigmacta Pro ─────────────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ProScreen(user: user))),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.accent, c.accent3]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sigmacta Pro',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      Text(context.t('proSettingsSub'),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
          const SizedBox(height: 26),

          // ── Account ─────────────────────────────────────────────────
          _label(c, context.t('secAccount')),
          const SizedBox(height: 10),
          _tile(c, Icons.person_outline_rounded, context.t('editProfileBtn'),
              () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      OnboardingScreen(user: user, editMode: true)),
            );
          }),
          const SizedBox(height: 26),

          // ── Appearance ───────────────────────────────────────────────
          _label(c, context.t('secAppearance')),
          const SizedBox(height: 10),
          _label(c, context.t('theme')),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < kThemes.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _choice(
                    c,
                    lang == 'ru' ? kThemes[i].nameRu : kThemes[i].nameEn,
                    config.themeIndex == i,
                    () => _setTheme(i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _label(c, context.t('pickLang')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _choice(c, '🇷🇺 ${context.t('russian')}', lang == 'ru',
                    () => _setLang('ru'))),
            const SizedBox(width: 10),
            Expanded(
                child: _choice(c, '🇬🇧 ${context.t('english')}', lang == 'en',
                    () => _setLang('en'))),
          ]),
          const SizedBox(height: 26),

          // ── About (Google Play compliance) ───────────────────────────
          _label(c, context.t('secAbout')),
          const SizedBox(height: 10),
          _tile(c, Icons.privacy_tip_outlined, context.t('privacyPolicy'),
              () => _open(_privacyUrl)),
          const SizedBox(height: 8),
          _tile(c, Icons.description_outlined, context.t('termsOfUse'),
              () => _open(_termsUrl)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: c.inkSoft, size: 20),
              const SizedBox(width: 12),
              Text(context.t('appVersion'),
                  style: TextStyle(color: c.ink, fontSize: 14)),
              const Spacer(),
              Text(_version, style: TextStyle(color: c.inkSoft, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 34),

          // ── Logout / delete ──────────────────────────────────────────
          GestureDetector(
            onTap: () => _logout(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.danger.withOpacity(0.4)),
              ),
              child: Text(context.t('logout'),
                  style: TextStyle(
                      color: c.danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _deleteAccount(context),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(context.t('deleteAccount'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 13,
                      decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BrutalColors c, String t) => Text(t,
      style: TextStyle(
          fontWeight: FontWeight.w700, fontSize: 13, color: c.inkSoft));

  Widget _tile(BrutalColors c, IconData icon, String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(icon, color: c.ink, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: TextStyle(color: c.ink, fontSize: 14))),
          Icon(Icons.chevron_right_rounded, color: c.inkSoft),
        ]),
      ),
    );
  }

  Widget _choice(BrutalColors c, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accent.withOpacity(0.16) : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active ? c.accent : c.ink.withOpacity(0.08),
              width: active ? 1.4 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? c.ink : c.inkSoft,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      ),
    );
  }
}
