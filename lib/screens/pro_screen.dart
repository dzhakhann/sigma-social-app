import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

/// Sigmacta Pro — subscription upsell. Real payment is wired via Google Play
/// Billing at publish time; for now the button explains it's coming.
class ProScreen extends StatelessWidget {
  final Map user;
  const ProScreen({Key? key, required this.user}) : super(key: key);

  static const _benefits = [
    ['verified_rounded', 'proB1t', 'proB1d'],
    ['block_rounded', 'proB2t', 'proB2d'],
    ['auto_awesome_rounded', 'proB3t', 'proB3d'],
    ['insights_rounded', 'proB4t', 'proB4d'],
    ['palette_rounded', 'proB5t', 'proB5d'],
  ];

  IconData _icon(String k) {
    switch (k) {
      case 'verified_rounded': return Icons.verified_rounded;
      case 'block_rounded': return Icons.block_rounded;
      case 'auto_awesome_rounded': return Icons.auto_awesome_rounded;
      case 'insights_rounded': return Icons.insights_rounded;
      case 'palette_rounded': return Icons.palette_rounded;
      default: return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.t('proTitle'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.accent3]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(context.t('proTitle'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                Text(context.t('proSubtitle'),
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 18),

          ..._benefits.map((b) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.ink.withOpacity(0.06))),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(_icon(b[0]), color: c.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t(b[1]),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: c.ink)),
                        const SizedBox(height: 2),
                        Text(context.t(b[2]),
                            style: TextStyle(color: c.inkSoft, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ]),
              )),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(context.t('proComingSoon'))));
              },
              child: Text(context.t('proBuyBtn'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.t('proFootnote'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
