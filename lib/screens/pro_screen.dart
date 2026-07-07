import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';

/// Sigmacta Pro — subscription upsell. Real payment is wired via Google Play
/// Billing at publish time; for now the button explains it's coming.
class ProScreen extends StatelessWidget {
  final Map user;
  const ProScreen({Key? key, required this.user}) : super(key: key);

  static const _benefits = [
    ['verified_rounded', 'Галочка верификации', 'Синяя галочка рядом с именем — доверие и статус.'],
    ['block_rounded', 'Без рекламы', 'Чистая лента и профиль без промо-блоков.'],
    ['auto_awesome_rounded', 'Больше ИИ', 'Расширенные лимиты ИИ-коуча и рекомендаций.'],
    ['insights_rounded', 'Продвинутая аналитика целей', 'Глубокая статистика прогресса и графики.'],
    ['palette_rounded', 'Эксклюзивные темы и рамки', 'Оформление профиля, доступное только Pro.'],
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
      appBar: AppBar(title: const Text('Sigmacta Pro')),
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
                  const Text('Sigmacta Pro',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                Text('Раскрой максимум: статус, чистый интерфейс и больше ИИ.',
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
                        Text(b[1],
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: c.ink)),
                        const SizedBox(height: 2),
                        Text(b[2],
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
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Оплата подключится при публикации в Google Play. Скоро!')));
              },
              child: const Text('Оформить Pro',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Подписка активируется через Google Play после публикации приложения. '
            'Оплата и управление — в аккаунте Google Play.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
