import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/session.dart';
import 'login_screen.dart';
import 'pro_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Map user;
  const SettingsScreen({super.key, required this.user});

  void _setLang(String l) =>
      appConfig.value = appConfig.value.copyWith(lang: l);

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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sigmacta Pro',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      Text('Галочка · без рекламы · больше ИИ',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ]),
            ),
          ),
          const SizedBox(height: 26),

          // ── Language ─────────────────────────────────────────────────
          _label(c, context.t('pickLang')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _choice(c, '🇷🇺 ${context.t('russian')}', lang == 'ru',
                    () => _setLang('ru'))),
            const SizedBox(width: 10),
            Expanded(
                child: _choice(c, '🇬🇧 ${context.t('english')}', lang == 'en',
                    () => _setLang('en'))),
          ]),
          const SizedBox(height: 34),

          // ── Logout ───────────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              await Session.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
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
        ],
      ),
    );
  }

  Widget _label(BrutalColors c, String t) => Text(t,
      style: TextStyle(
          fontWeight: FontWeight.w700, fontSize: 13, color: c.inkSoft));

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
