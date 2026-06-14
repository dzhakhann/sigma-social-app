import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';
import '../services/session.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Map user;
  const SettingsScreen({super.key, required this.user});

  void _setTheme(int i) =>
      appConfig.value = appConfig.value.copyWith(themeIndex: i);
  void _setLang(String l) =>
      appConfig.value = appConfig.value.copyWith(lang: l);
  void _setNav(String s) =>
      appConfig.value = appConfig.value.copyWith(navSide: s);

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final config = AppScope.of(context).config;
    final lang = config.lang;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.t('settings')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── LANGUAGE ────────────────────────────────────────────────
          Text(
            context.t('pickLang'),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17, color: c.ink),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LangCard(
                  flag: '🇷🇺',
                  label: context.t('russian'),
                  active: lang == 'ru',
                  onTap: () => _setLang('ru'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LangCard(
                  flag: '🇬🇧',
                  label: context.t('english'),
                  active: lang == 'en',
                  onTap: () => _setLang('en'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          // ── NAVIGATION SIDE ─────────────────────────────────────────
          Text(
            context.t('navigation'),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17, color: c.ink),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LangCard(
                  flag: '➡️',
                  label: context.t('navRight'),
                  active: config.navSide != 'left',
                  onTap: () => _setNav('right'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LangCard(
                  flag: '⬅️',
                  label: context.t('navLeft'),
                  active: config.navSide == 'left',
                  onTap: () => _setNav('left'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),
          // ── PREVIEW ─────────────────────────────────────────────────
          BrutalLabel(context.t('preview'), fill: c.accent2),
          const SizedBox(height: 12),
          _PreviewCard(user: user),

          const SizedBox(height: 28),
          // ── ACCOUNT ─────────────────────────────────────────────────
          BrutalLabel(context.t('account'), fill: c.accent3),
          const SizedBox(height: 12),
          BrutalTap(
            fill: c.danger,
            radius: 14,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shadowOffset: const Offset(4, 4),
            onTap: () {
              Session.clear();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: Center(
              child: Text(
                context.t('logout'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final BrutalTheme theme;
  final String lang;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeRow({
    required this.theme,
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k; // current theme (for the row container border)
    final p = theme.c; // the palette this row represents
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? c.accent2 : c.ink,
              width: selected ? 3.5 : 2.5),
          boxShadow: [
            BoxShadow(
                color: c.shadow,
                offset: selected ? const Offset(2, 2) : const Offset(5, 5))
          ],
        ),
        child: Row(
          children: [
            // mini palette preview block
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.ink, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(child: Container(color: p.accent)),
                  Row(
                    children: [
                      Expanded(child: Container(color: p.accent2, height: 20)),
                      Expanded(child: Container(color: p.accent3, height: 20)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lang == 'ru' ? theme.nameRu : theme.nameEn,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.isDark ? '◑ dark' : '◐ light',
                    style: TextStyle(fontSize: 12, color: c.inkSoft),
                  ),
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? c.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: c.ink, width: 2.5),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 18, color: c.onAccent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  final String flag;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _LangCard({
    required this.flag,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: active ? c.accent : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.ink, width: active ? 3 : 2.5),
          boxShadow: [
            BoxShadow(
                color: c.shadow,
                offset: active ? const Offset(2, 2) : const Offset(4, 4))
          ],
        ),
        child: Column(
          children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: active ? c.onAccent : c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final Map user;
  const _PreviewCard({required this.user});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final username = (user['username'] ?? 'you').toString();
    return BrutalCard(
      fill: c.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.ink, width: 2),
                ),
                child: Icon(Icons.face_rounded, color: c.onAccent),
              ),
              const SizedBox(width: 10),
              Text('@$username',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: c.ink, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.t('sampleCard'),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniChip(c, Icons.favorite_rounded, c.danger),
              const SizedBox(width: 8),
              _miniChip(c, Icons.mode_comment_outlined, c.accent2),
              const SizedBox(width: 8),
              _miniChip(c, Icons.rocket_launch_rounded, c.accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip(BrutalColors c, IconData icon, Color fill) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.ink, width: 2),
      ),
      child: Icon(icon, size: 16, color: c.onAccent),
    );
  }
}
