import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../l10n/app_strings.dart';
import '../services/notification_prefs.dart';
import '../services/pro_state.dart';
import '../theme/brutal_theme.dart';

/// Notification preferences: master switch, sound/vibration/preview/LED, a
/// tone picker that previews on tap, and a per-category list.
///
/// Everything here is device-local (see [NotificationPrefs]) — it controls how
/// this phone reacts to an incoming event, not what the server sends.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _preview = AudioPlayer();

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  /// Plays the tone so the choice can be judged by ear rather than by name.
  /// Silently does nothing when the asset is missing, so an unshipped tone
  /// can still be selected instead of throwing.
  Future<void> _playTone(String tone) async {
    try {
      await _preview.stop();
      await _preview.play(AssetSource('sounds/notif_$tone.wav'), volume: 0.9);
    } catch (_) {}
  }

  Future<void> _buzz() async {
    try {
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(duration: 60);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('notifSettingsTitle'))),
      body: ValueListenableBuilder<NotificationSettings>(
        valueListenable: NotificationPrefs.value,
        builder: (_, s, __) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _card(c, [
              _switchRow(c, context.t('notifMaster'),
                  context.t('notifMasterSub'), s.enabled,
                  (v) => NotificationPrefs.setEnabled(v)),
            ]),
            const SizedBox(height: 22),

            // Everything below only matters while notifications are on, so it
            // dims and stops responding rather than silently doing nothing.
            Opacity(
              opacity: s.enabled ? 1 : 0.4,
              child: IgnorePointer(
                ignoring: !s.enabled,
                child: Column(children: [
                  _label(c, context.t('notifSecHow')),
                  const SizedBox(height: 10),
                  _card(c, [
                    _switchRow(c, context.t('notifSound'), '', s.soundOn,
                        (v) => NotificationPrefs.setSoundOn(v)),
                    _divider(c),
                    _switchRow(c, context.t('notifVibrate'), '', s.vibrate,
                        (v) async {
                      await NotificationPrefs.setVibrate(v);
                      if (v) _buzz();
                    }),
                    _divider(c),
                    _switchRow(c, context.t('notifPreview'),
                        context.t('notifPreviewSub'), s.preview,
                        (v) => NotificationPrefs.setPreview(v)),
                    _divider(c),
                    _switchRow(c, context.t('notifLed'), '', s.led,
                        (v) => NotificationPrefs.setLed(v)),
                  ]),
                  const SizedBox(height: 22),

                  _label(c, context.t('notifSecTone')),
                  const SizedBox(height: 10),
                  _card(c, [
                    for (var i = 0; i < NotificationPrefs.sounds.length; i++) ...[
                      if (i > 0) _divider(c),
                      _toneRow(c, NotificationPrefs.sounds[i], s.tone),
                    ],
                  ]),
                  const SizedBox(height: 22),

                  _label(c, context.t('notifSecCats')),
                  const SizedBox(height: 10),
                  _card(c, [
                    for (var i = 0;
                        i < NotificationPrefs.categories.length;
                        i++) ...[
                      if (i > 0) _divider(c),
                      _switchRow(
                        c,
                        context.t('notifCat_${NotificationPrefs.categories[i]}'),
                        '',
                        !s.disabled.contains(NotificationPrefs.categories[i]),
                        (v) => NotificationPrefs.setCategory(
                            NotificationPrefs.categories[i], v),
                      ),
                    ],
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BrutalColors c, String t) => Align(
        alignment: Alignment.centerLeft,
        child: Text(t,
            style: TextStyle(
                color: c.inkSoft,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4)),
      );

  Widget _card(BrutalColors c, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.ink.withOpacity(0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _divider(BrutalColors c) =>
      Divider(height: 1, thickness: 1, color: c.ink.withOpacity(0.05));

  Widget _switchRow(BrutalColors c, String title, String sub, bool value,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      color: c.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub,
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: c.accentFill,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _toneRow(BrutalColors c, String tone, String selected) {
    final active = tone == selected;
    final locked = !NotificationPrefs.isFreeSound(tone) && !ProState.isPro.value;
    return InkWell(
      // A locked tone still PREVIEWS on tap — you have to hear it to want it.
      // Only selecting it is gated.
      onTap: () {
        _playTone(tone);
        if (locked) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.t('notifToneProOnly'))));
          return;
        }
        NotificationPrefs.setTone(tone);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          Icon(active ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19, color: active ? c.accent : c.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(context.t('notifTone_$tone'),
                style: TextStyle(
                    color: c.ink,
                    fontSize: 14.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ),
          if (locked) ...[
            Icon(Icons.lock_rounded, size: 14, color: c.accent3),
            const SizedBox(width: 8),
          ],
          Icon(Icons.play_arrow_rounded, size: 20, color: c.inkSoft),
        ]),
      ),
    );
  }
}
