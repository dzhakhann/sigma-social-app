import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'profile_screen.dart';

/// "Обмен профилем" — show your QR or scan someone else's to open their
/// profile instantly. No contacts needed (like exchanging business cards).
class ProfileShareScreen extends StatefulWidget {
  final Map user;
  const ProfileShareScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<ProfileShareScreen> createState() => _ProfileShareScreenState();
}

class _ProfileShareScreenState extends State<ProfileShareScreen> {
  int _mode = 0; // 0 = my QR, 1 = scan
  bool _handled = false;

  String get _qrData => 'sigmacta://u/${widget.user['id']}';

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      String? id;
      if (raw.contains('u/')) {
        id = raw.split('u/').last.trim();
      } else if (raw.isNotEmpty) {
        id = raw.trim();
      }
      if (id != null && id.isNotEmpty && id != widget.user['id'].toString()) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(
              user: widget.user,
              targetUserId: id,
              isOwnProfile: false,
            ),
          ),
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text(context.t('profileShareTitle')),
      ),
      body: Column(children: [
        // Toggle
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: c.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            _tab(c, 0, Icons.qr_code_2_rounded, context.t('myQr')),
            _tab(c, 1, Icons.qr_code_scanner_rounded, context.t('scanQr')),
          ]),
        ),
        Expanded(
          child: _mode == 0 ? _myQr(c) : _scanner(c),
        ),
      ]),
    );
  }

  Widget _tab(BrutalColors c, int i, IconData icon, String label) {
    final sel = _mode == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _mode = i; _handled = false; }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: sel ? c.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(11)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: sel ? c.onAccent : c.inkSoft),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: sel ? c.onAccent : c.inkSoft,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _myQr(BrutalColors c) {
    final name =
        (widget.user['first_name'] ?? widget.user['username'] ?? context.t('profileFallback'))
            .toString();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: QrImageView(
              data: _qrData,
              version: QrVersions.auto,
              size: 230,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(name,
              style: TextStyle(
                  color: c.ink, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('@${widget.user['username'] ?? ''}',
              style: TextStyle(color: c.inkSoft, fontSize: 14)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              context.t('qrShowHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanner(BrutalColors c) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MobileScanner(onDetect: _onDetect),
          ),
        ),
        // Framing overlay
        Container(
          width: 230,
          height: 230,
          decoration: BoxDecoration(
            border: Border.all(color: c.accent, width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        Positioned(
          bottom: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20)),
            child: Text(context.t('qrScanHint'),
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}
