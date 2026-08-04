import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../services/api_service.dart';

/// Apply for the blue verification checkmark. Requests go to the admin panel;
/// re-application is blocked for 365 days (enforced server-side).
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final _email = TextEditingController();
  final _wiki = TextEditingController();
  final _info = TextEditingController();
  bool _sending = false;

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    final r = await ApiService.applyVerification(
        email: _email.text.trim(),
        wiki: _wiki.text.trim(),
        info: _info.text.trim());
    if (!mounted) return;
    setState(() => _sending = false);
    if (r['success'] == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('verifySent'))));
      Navigator.pop(context);
    } else if (r['error'] == 'already_applied') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context
              .t('verifyWait')
              .replaceAll('{n}', '${r['days_left'] ?? 365}'))));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((r['error'] ?? context.t('connError')).toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('verifBadge'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          Row(children: [
            Icon(Icons.verified_rounded, color: c.accent, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(context.t('verifyDesc'),
                  style: TextStyle(color: c.inkSoft, height: 1.4)),
            ),
          ]),
          const SizedBox(height: 22),
          _field(c, _email, context.t('verifyEmail'),
              keyboard: TextInputType.emailAddress),
          const SizedBox(height: 14),
          _field(c, _wiki, context.t('verifyWiki'),
              keyboard: TextInputType.url),
          const SizedBox(height: 14),
          _field(c, _info, context.t('verifyInfo'), maxLines: 5),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: c.accentFill,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(context.t('verifySubmit'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BrutalColors c, TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      style: TextStyle(color: c.ink),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _wiki.dispose();
    _info.dispose();
    super.dispose();
  }
}
