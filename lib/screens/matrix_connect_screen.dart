import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../constants.dart';
import '../services/matrix_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import '../widgets/brutal.dart';

/// Shown when Matrix session is missing or login failed.
class MatrixConnectScreen extends StatefulWidget {
  final Map user;
  final String? initialError;

  const MatrixConnectScreen({
    super.key,
    required this.user,
    this.initialError,
  });

  @override
  State<MatrixConnectScreen> createState() => _MatrixConnectScreenState();
}

class _MatrixConnectScreenState extends State<MatrixConnectScreen> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(
      text: (widget.user['username'] ?? '').toString(),
    );
    _passCtrl = TextEditingController();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await MatrixService.instance.loginOrRegister(
      _userCtrl.text,
      _passCtrl.text,
    );

    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.t('matrixChat')),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          BrutalLabel('SECURE CHAT', fill: c.accent),
          const SizedBox(height: 12),
          Text(
            'Chats run on Matrix ($kMatrixServerName), separate from Sigma posts. '
            'Messages are end-to-end encrypted.',
            style: TextStyle(color: c.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.danger.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: c.danger)),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _userCtrl,
            enabled: !_loading,
            decoration: InputDecoration(
              labelText: context.t('matrixUsername'),
              hintText: context.t('matrixNoAt'),
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            enabled: !_loading,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.t('matrixPassword'),
              filled: true,
              fillColor: c.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'POC: use an existing @$kMatrixServerName account, or your own '
            'homeserver once Conduit is deployed.',
            style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 20),
          BrutalTap(
            fill: c.accent,
            radius: 14,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: _loading ? null : _connect,
            child: Center(
              child: _loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onAccent,
                      ),
                    )
                  : Text(
                      'Connect',
                      style: TextStyle(
                        color: c.onAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
