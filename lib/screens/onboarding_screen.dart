import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'main_screen.dart';

/// Shown once right after registration. Collects the full profile (everything
/// optional). Each field has a show/hide (eye) toggle that controls whether it
/// is public on the profile. Saved via updateUser + hidden_fields.
class OnboardingScreen extends StatefulWidget {
  final Map user;
  final bool editMode; // true = editing existing profile (pop on save)
  const OnboardingScreen({Key? key, required this.user, this.editMode = false})
      : super(key: key);
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _middle = TextEditingController();
  final _birthday = TextEditingController();
  final _birthplace = TextEditingController();
  final _education = TextEditingController();
  final _work = TextEditingController();
  final _website = TextEditingController();
  final _skills = TextEditingController();
  final _about = TextEditingController();

  String? _gender;
  String? _relationship;
  bool _saving = false;

  // Field keys the user chose to HIDE from the public profile.
  final Set<String> _hidden = {};

  String get _uid => widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _first.text = (u['first_name'] ?? '').toString();
    _last.text = (u['last_name'] ?? '').toString();
    _middle.text = (u['middle_name'] ?? '').toString();
    _birthday.text = (u['birthday'] ?? '').toString();
    _birthplace.text = (u['birthplace'] ?? '').toString();
    _education.text = (u['education'] ?? '').toString();
    _work.text = (u['work'] ?? '').toString();
    _website.text = (u['website'] ?? '').toString();
    _skills.text = (u['skills'] ?? '').toString();
    _about.text = (u['about'] ?? '').toString();
    if ((u['gender'] ?? '').toString().isNotEmpty) _gender = u['gender'];
    if ((u['relationship'] ?? '').toString().isNotEmpty) {
      _relationship = u['relationship'];
    }
    final hf = u['hidden_fields'];
    if (hf is List) _hidden.addAll(hf.map((e) => e.toString()));
  }

  // Canonical ids — stored in the DB, translated only for display.
  static const _genders = ['male', 'female', 'other_gender'];
  static const _relationships = [
    'single', 'relationship', 'married', 'complicated',
  ];

  Future<void> _finish({bool skip = false}) async {
    if (skip) {
      _goHome();
      return;
    }
    setState(() => _saving = true);
    final fields = {
      'first_name': _first.text.trim(),
      'last_name': _last.text.trim(),
      'middle_name': _middle.text.trim(),
      'birthday': _birthday.text.trim(),
      'gender': canonicalProfileValue(_gender ?? ''),
      'birthplace': _birthplace.text.trim(),
      'education': _education.text.trim(),
      'work': _work.text.trim(),
      'website': _website.text.trim(),
      'relationship': canonicalProfileValue(_relationship ?? ''),
      'skills': _skills.text.trim(),
      'about': _about.text.trim(),
      'hidden_fields': _hidden.toList(),
    };
    await ApiService.updateUser(_uid, fields);
    // Merge into the in-memory user so the profile shows data immediately.
    widget.user.addAll(fields);
    if (widget.editMode) {
      if (mounted) Navigator.pop(context, true);
    } else {
      _goHome();
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MainScreen(user: Map.from(widget.user)),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(widget.editMode
            ? context.t('obTitleEdit')
            : context.t('obTitleNew')),
        actions: [
          if (!widget.editMode)
            TextButton(
              onPressed: _saving ? null : () => _finish(skip: true),
              child: Text(context.t('later'), style: TextStyle(color: c.inkSoft)),
            ),
        ],
      ),
      body: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
              offset: Offset(0, (1 - v) * 26), child: child),
        ),
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                c.accent.withOpacity(0.18),
                c.accent3.withOpacity(0.10)
              ]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded, color: c.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t('obIntro'),
                  style: TextStyle(color: c.ink, height: 1.4, fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),

          _section(c, Icons.badge_outlined, context.t('secName')),
          _field(c, 'name', context.t('fFirst'), _first),
          _field(c, 'name', context.t('fLast'), _last, showEye: false),
          _field(c, 'name', context.t('fMiddle'), _middle, showEye: false),

          _section(c, Icons.info_outline_rounded, context.t('secBasic')),
          _field(c, 'birthday', context.t('fBirthday'), _birthday),
          _chips(c, 'gender', context.t('fGender'), _genders, _gender,
              (v) => setState(() => _gender = v)),
          _field(c, 'birthplace', context.t('fBirthplace'), _birthplace),

          _section(c, Icons.school_outlined, context.t('secEdu')),
          _field(c, 'education', context.t('fEducation'), _education),
          _field(c, 'work', context.t('fWork'), _work),

          _section(c, Icons.auto_awesome_outlined, context.t('secMore')),
          _field(c, 'website', context.t('fWebsite'), _website),
          _chips(c, 'relationship', context.t('fRelationship'), _relationships,
              _relationship, (v) => setState(() => _relationship = v)),
          _field(c, 'skills', context.t('fSkills'), _skills, maxLines: 3),
          _field(c, 'about', context.t('fAbout'), _about, maxLines: 3),

          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _saving ? null : () => _finish(),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(context.t('saveContinue'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _section(BrutalColors c, IconData icon, String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: c.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 15, color: c.accent),
          ),
          const SizedBox(width: 8),
          Text(t,
              style: TextStyle(
                  color: c.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
        ]),
      );

  Widget _eye(BrutalColors c, String key) {
    final hidden = _hidden.contains(key);
    return IconButton(
      tooltip: hidden ? context.t('hiddenTip') : context.t('visibleTip'),
      visualDensity: VisualDensity.compact,
      icon: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          size: 20, color: hidden ? c.inkSoft : c.accent),
      onPressed: () => setState(() {
        if (hidden) {
          _hidden.remove(key);
        } else {
          _hidden.add(key);
        }
      }),
    );
  }

  Widget _field(BrutalColors c, String key, String hint,
      TextEditingController ctrl,
      {int maxLines = 1, bool showEye = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: maxLines,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint, isDense: true),
            ),
          ),
          if (showEye) _eye(c, key) else const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _chips(BrutalColors c, String key, String label, List<String> options,
      String? selected, ValueChanged<String> onSel) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(label,
                      style: TextStyle(color: c.inkSoft, fontSize: 13)),
                ),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: options.map((o) {
                    final sel = canonicalProfileValue(o) ==
                        canonicalProfileValue(selected ?? '');
                    return GestureDetector(
                      onTap: () => onSel(o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.accent.withOpacity(0.18) : c.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: sel ? c.accent : Colors.transparent,
                              width: 1.2),
                        ),
                        child: Text(localizedProfileValue(context, o),
                            style: TextStyle(
                                color: sel ? c.ink : c.inkSoft,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          _eye(c, key),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final ctrl in [
      _first, _last, _middle, _birthday, _birthplace,
      _education, _work, _website, _skills, _about,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }
}
