import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';

/// Lightweight, dependency-free emoji picker. A button next to a text field
/// that opens a categorized emoji panel and inserts at the cursor.

class _EmojiCat {
  final String icon;
  final List<String> emojis;
  const _EmojiCat(this.icon, this.emojis);
}

const List<_EmojiCat> _cats = [
  _EmojiCat('😀', [
    '😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🙂','🙃','😉','😌','😍',
    '🥰','😘','😗','😙','😚','😋','😛','😝','😜','🤪','🤨','🧐','🤓','😎','🥳',
    '🤩','😏','😒','😔','😟','😕','🙁','☹️','😣','😖','😫','😩','🥺','😢','😭',
    '😤','😠','😡','🤬','🤯','😳','🥵','🥶','😱','😨','😰','😥','😓','🤗','🤔',
    '🤭','🥱','😴','🤤','😪','😷','🤒','🤕','🤢','🤮','🥴','😵','🤠','😈','👻',
  ]),
  _EmojiCat('👍', [
    '👍','👎','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️',
    '✋','🤚','🖐️','🖖','👋','🤝','🙏','💪','🦾','🙌','👏','🤲','🫶','👐','✊',
    '👊','🤛','🤜','✍️','💅','🤳',
  ]),
  _EmojiCat('❤️', [
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗',
    '💖','💘','💝','⭐','🌟','✨','⚡','🔥','💯','✅','❌','❓','❗','💢','💥',
    '💫','💦','🎉','🎊','🎁','🏆','🥇','👑',
  ]),
  _EmojiCat('🐶', [
    '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵',
    '🐔','🐧','🐦','🦆','🦅','🦉','🐴','🦄','🐝','🦋','🐢','🐍','🐙','🦈','🐬',
    '🐳','🐋','🐟','🌸','🌼','🌻','🌹','🌷','🌲','🌵','🍀','🌍',
  ]),
  _EmojiCat('🍔', [
    '🍎','🍌','🍇','🍓','🍒','🍑','🥭','🍍','🥥','🍅','🥑','🌽','🍞','🧀','🍗',
    '🍔','🍟','🍕','🌭','🌮','🍜','🍣','🍦','🍩','🍪','🎂','🍰','🍫','🍬','🍭',
    '☕','🍺','🍷','🥤','🍾',
  ]),
  _EmojiCat('⚽', [
    '⚽','🏀','🏈','⚾','🎾','🏐','🎱','🏓','🏸','🥊','🏆','🥇','🎮','🎲','🎯',
    '🎸','🎺','🎨','🎬','🎧','📚','✈️','🚗','🏠','💼','📱','💻','⌚','📷','🔑',
    '💡','🎓','💰','⏰',
  ]),
  _EmojiCat('🇷🇺', [
    '🇷🇺','🇺🇿','🇰🇿','🇺🇸','🇬🇧','🇩🇪','🇫🇷','🇮🇹','🇪🇸','🇹🇷','🇺🇦','🇨🇳',
    '🇯🇵','🇰🇷','🇮🇳','🇧🇷','🇨🇦','🇦🇪','🏳️','🏴','🏁','🚩',
  ]),
];

class EmojiPickerButton extends StatelessWidget {
  final TextEditingController controller;
  final Color? color;
  const EmojiPickerButton({super.key, required this.controller, this.color});

  void _insert(String e) {
    final sel = controller.selection;
    final text = controller.text;
    final start = (sel.start < 0 ? text.length : sel.start).clamp(0, text.length);
    final end = (sel.end < 0 ? text.length : sel.end).clamp(0, text.length);
    controller.text = text.replaceRange(start, end, e);
    controller.selection = TextSelection.collapsed(offset: start + e.length);
  }

  void _show(BuildContext context) {
    final c = context.k;
    int cat = 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: 330,
          child: Column(children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2)),
            ),
            SizedBox(
              height: 46,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _cats.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setSheet(() => cat = i),
                  child: Container(
                    width: 46,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    decoration: BoxDecoration(
                        color: cat == i ? c.accent.withOpacity(0.18) : null,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(_cats[i].icon, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: c.ink.withOpacity(0.06)),
            Expanded(
              child: GridView.count(
                crossAxisCount: 8,
                padding: const EdgeInsets.all(6),
                children: _cats[cat].emojis
                    .map((e) => GestureDetector(
                          onTap: () => _insert(e),
                          child: Center(
                              child: Text(e, style: const TextStyle(fontSize: 24))),
                        ))
                    .toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.emoji_emotions_outlined, color: color ?? c.inkSoft),
      onPressed: () => _show(context),
    );
  }
}
