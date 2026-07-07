import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../screens/ai_chat_screen.dart';
import '../screens/goals_screen.dart';

/// AI recommendations card (based on the user's goals). Shown on the
/// Recommendations tab.
class AiRecoCard extends StatefulWidget {
  final Map user;
  const AiRecoCard({super.key, required this.user});
  @override
  State<AiRecoCard> createState() => _AiRecoCardState();
}

class _AiRecoCardState extends State<AiRecoCard> {
  String? _text;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await ApiService.aiRecommend();
    if (mounted) setState(() { _text = t; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c.accent.withOpacity(0.16), c.accent3.withOpacity(0.10)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: c.accent),
            const SizedBox(width: 8),
            Text('Рекомендации ИИ',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: c.ink)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AiChatScreen(user: widget.user)),
              ),
              child: Text('Спросить →',
                  style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 10),
          if (_loading)
            Row(children: [
              SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.accent)),
              const SizedBox(width: 10),
              Text('Собираю советы по твоим целям…',
                  style: TextStyle(color: c.inkSoft, fontSize: 13)),
            ])
          else
            Text(_text ?? '',
                style: TextStyle(color: c.ink, fontSize: 14, height: 1.4)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GoalsScreen(user: widget.user)),
            ),
            child: Row(children: [
              Icon(Icons.track_changes_rounded, size: 16, color: c.accent),
              const SizedBox(width: 6),
              Text('Мои цели и годовой отчёт →',
                  style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
          ),
        ],
      ),
    );
  }
}
