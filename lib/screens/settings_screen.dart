import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/pro_state.dart';
import '../services/session.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'notification_settings_screen.dart';
import 'pro_screen.dart';
import 'onboarding_screen.dart';
import 'verification_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Map user;
  const SettingsScreen({super.key, required this.user});

  static const String _privacyUrl = 'https://sigmacta.pages.dev/privacy';
  static const String _termsUrl = 'https://sigmacta.pages.dev/terms';

  void _setLang(String l) =>
      appConfig.value = appConfig.value.copyWith(lang: l);

  /// Boys and Girls are Premium: they carry their own ambience, effects and
  /// atmosphere, not just a palette. Checked here AND enforced at startup (see
  /// [enforceThemeEntitlement]) so a lapsed subscription can't leave someone on
  /// a theme they no longer have.
  static const _premiumThemeIds = {'boys', 'girls'};

  bool _isPremiumTheme(int i) => _premiumThemeIds.contains(kThemes[i].id);

  /// Reads the reactive flag, NOT `user['is_pro']`. The `user` map is
  /// snapshotted at startup and handed down the tree, so it still said false
  /// right after a promo code was redeemed — which is exactly why Premium
  /// themes stayed locked while the profile screen already showed PRO.
  bool get _hasPro => ProState.isPro.value;

  void _setTheme(BuildContext context, int i) {
    if (_isPremiumTheme(i) && !_hasPro) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProScreen(user: user)));
      return;
    }
    appConfig.value = appConfig.value.copyWith(themeIndex: i);
  }

  // externalApplication alone has been unreliable on some devices/configs
  // elsewhere in this app (see story_view_screen.dart) — same two-step
  // fallback here, plus a visible error instead of silently doing nothing
  // when both attempts fail, so a real failure is at least reported rather
  // than looking identical to "nothing happened, why?".
  //
  // On web specifically, LaunchMode.externalApplication opens a new tab via
  // window.open() — by the time that call reaches the browser it's a couple
  // async hops removed from the actual click (through Flutter's own gesture
  // dispatch), which is often enough for popup blockers to silently kill it,
  // and BOTH modes route through the same window.open on web, so the
  // fallback above didn't help there. webOnlyWindowName: '_self' sidesteps
  // this entirely by navigating the current tab instead of opening one —
  // ignored on native, and there's no popup to block for a same-tab nav.
  Future<void> _open(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_self');
      return;
    } catch (_) {}
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.platformDefault, webOnlyWindowName: '_self');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t('linkOpenFailed'))));
      }
    }
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
          const SizedBox(height: 8),
          _tile(c, Icons.verified_outlined, context.t('verifBadge'), () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerificationScreen()),
            );
          }),
          const SizedBox(height: 26),

          // ── Notifications ────────────────────────────────────────────
          _label(c, context.t('notifSettingsTitle')),
          const SizedBox(height: 10),
          _tile(c, Icons.notifications_active_outlined,
              context.t('notifSettingsTitle'), () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()));
          }),
          const SizedBox(height: 26),

          // ── Appearance ───────────────────────────────────────────────
          _label(c, context.t('secAppearance')),
          const SizedBox(height: 10),
          _label(c, context.t('theme')),
          const SizedBox(height: 8),
          // Two per row — a single Row of Expanded chips got unreadably
          // narrow once the palette list grew past two themes.
          ValueListenableBuilder<bool>(
              valueListenable: ProState.isPro,
              builder: (_, __, ___) => LayoutBuilder(builder: (_, box) {
            final w = (box.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 0; i < kThemes.length; i++)
                  SizedBox(
                    width: w,
                    child: _themeChoice(
                      c,
                      kThemes[i],
                      lang == 'ru' ? kThemes[i].nameRu : kThemes[i].nameEn,
                      config.themeIndex == i,
                      () => _setTheme(context, i),
                      locked: _isPremiumTheme(i) && !_hasPro,
                    ),
                  ),
              ],
            );
          })),
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
              () => _open(context, _privacyUrl)),
          const SizedBox(height: 8),
          _tile(c, Icons.description_outlined, context.t('termsOfUse'),
              () => _open(context, _termsUrl)),
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
              // Read from the built package, never a hand-kept constant —
              // the old `_version = '1.2.0'` string had to be bumped in
              // lockstep with pubspec.yaml and silently went stale.
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (_, snap) => Text(
                    snap.hasData ? snap.data!.version : '',
                    style: TextStyle(color: c.inkSoft, fontSize: 14)),
              ),
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

  /// Theme chip with a live swatch of that palette's own background/accent —
  /// the names alone ("Boys"/"Girls") don't tell you what you're picking.
  Widget _themeChoice(BrutalColors c, BrutalTheme t, String label, bool active,
      VoidCallback onTap, {bool locked = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: active ? c.accent.withOpacity(0.16) : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: active ? c.accent : c.ink.withOpacity(0.08),
              width: active ? 1.4 : 1),
        ),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: t.c.bg,
              shape: BoxShape.circle,
              border: Border.all(color: c.ink.withOpacity(0.12)),
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: t.c.accent, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: active ? c.ink : c.inkSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
          // The theme stays visible and tappable when locked — tapping opens
          // Pro. Hiding it would leave no way to discover it exists.
          if (locked)
            Icon(Icons.lock_rounded, size: 15, color: c.accent3),
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
