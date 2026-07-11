import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';

// Keyword index for emoji search (EN + RU) — covers the popular ones.
const Map<String, String> _kw = {
  '😀': 'smile happy улыбка счастье', '😂': 'laugh lol смех ржака',
  '🤣': 'laugh rofl смех', '😍': 'love eyes любовь глаза',
  '🥰': 'love любовь мило', '😘': 'kiss поцелуй', '😎': 'cool круто очки',
  '🤔': 'think думать хм', '😢': 'cry sad плакать грусть',
  '😭': 'cry sob плакать рыдать', '😡': 'angry злой гнев',
  '🥳': 'party праздник', '😴': 'sleep сон спать', '🤯': 'mind blown взрыв',
  '😱': 'scream страх шок', '🤗': 'hug обнять', '🙃': 'upside перевернутый',
  '😉': 'wink подмигнуть', '🥺': 'please прошу мило',
  '👍': 'like thumbs лайк палец да', '👎': 'dislike нет палец',
  '👌': 'ok ок хорошо', '✌️': 'peace мир победа', '🤝': 'handshake рукопожатие',
  '🙏': 'pray please спасибо прошу молитва', '👏': 'clap аплодисменты хлопать',
  '💪': 'strong сила мышцы', '🤙': 'call звонок шака', '👋': 'wave hi привет пока',
  '✍️': 'write писать', '🫶': 'heart hands сердце руки',
  '❤️': 'heart love сердце любовь', '🧡': 'heart orange сердце',
  '💛': 'heart yellow сердце', '💚': 'heart green сердце',
  '💙': 'heart blue сердце', '💜': 'heart purple сердце',
  '🖤': 'heart black сердце', '💔': 'broken heart разбитое сердце',
  '💯': 'hundred 100 сто', '🔥': 'fire огонь', '✨': 'sparkles блеск звезды',
  '⭐': 'star звезда', '⚡': 'lightning молния энергия',
  '🎉': 'party congrats праздник поздравляю', '🎊': 'confetti конфетти',
  '🎁': 'gift подарок', '🏆': 'trophy кубок победа', '🥇': 'gold first золото',
  '🎯': 'target цель', '🚀': 'rocket ракета старт', '💡': 'idea лампа идея',
  '💰': 'money деньги', '💸': 'money деньги трата', '💎': 'diamond алмаз',
  '⏰': 'alarm будильник время', '📱': 'phone телефон', '💻': 'laptop ноутбук',
  '📚': 'books книги учеба', '✏️': 'pencil карандаш', '📝': 'note заметка',
  '🎵': 'music музыка нота', '🎧': 'headphones наушники',
  '🎤': 'microphone микрофон', '🎮': 'game игра геймпад',
  '⚽': 'football soccer футбол мяч', '🏀': 'basketball баскетбол',
  '🏋️': 'gym спортзал штанга', '🏃': 'run бег', '🚴': 'bike велосипед',
  '🧘': 'yoga йога медитация', '🏊': 'swim плавание',
  '🍕': 'pizza пицца', '🍔': 'burger бургер', '🍟': 'fries картошка',
  '☕': 'coffee кофе', '🍵': 'tea чай', '🍰': 'cake торт',
  '🍎': 'apple яблоко', '🍌': 'banana банан', '🍓': 'strawberry клубника',
  '🥑': 'avocado авокадо', '🍺': 'beer пиво', '🍷': 'wine вино',
  '🐶': 'dog собака', '🐱': 'cat кот кошка', '🦁': 'lion лев',
  '🐼': 'panda панда', '🦊': 'fox лиса', '🐻': 'bear медведь',
  '🦄': 'unicorn единорог', '🐝': 'bee пчела', '🦋': 'butterfly бабочка',
  '🌹': 'rose роза цветок', '🌸': 'flower цветок сакура',
  '🌞': 'sun солнце', '🌙': 'moon луна', '🌈': 'rainbow радуга',
  '❄️': 'snow снег зима', '🌊': 'wave волна море', '🌍': 'earth земля мир',
  '✈️': 'plane самолет путешествие', '🚗': 'car машина авто',
  '🏠': 'home дом', '🏖️': 'beach пляж', '⛰️': 'mountain гора',
  '💤': 'sleep сон', '💋': 'kiss поцелуй губы', '👀': 'eyes глаза смотрю',
  '🧠': 'brain мозг', '💀': 'skull череп смерть', '🤡': 'clown клоун',
  '👻': 'ghost призрак', '🤖': 'robot робот', '💩': 'poop какашка',
  '✅': 'check yes done готово да галочка', '❌': 'no cross нет крестик',
  '❓': 'question вопрос', '❗': 'exclamation восклицание',
  '➕': 'plus плюс', '🆗': 'ok ок',
};

/// Lightweight, dependency-free emoji picker. A button next to a text field
/// that opens a categorized emoji panel and inserts at the cursor.

class _EmojiCat {
  final String icon;
  final List<String> emojis;
  const _EmojiCat(this.icon, this.emojis);
}

const List<_EmojiCat> _cats = [
  _EmojiCat('😀', [
    '😀','😃','😄','😁','😆','😅','😂','🤣','🥲','☺️','😊','😇','🙂','🙃','😉',
    '😌','😍','🥰','😘','😗','😙','😚','😋','😛','😝','😜','🤪','🤨','🧐','🤓',
    '😎','🥸','🤩','🥳','😏','😒','😞','😔','😟','😕','🙁','☹️','😣','😖','😫',
    '😩','🥺','😢','😭','😮‍💨','😤','😠','😡','🤬','🤯','😳','🥵','🥶','😱','😨',
    '😰','😥','😓','🫠','🤗','🤔','🫡','🤭','🫢','🤫','🤥','😶','😶‍🌫️','😐','😑',
    '😬','🙄','😯','😦','😧','😮','😲','🥱','😴','🤤','😪','😵','😵‍💫','🫥','🤐',
    '🥴','🤢','🤮','🤧','😷','🤒','🤕','🤑','🤠','😈','👿','👹','👺','🤡','💩',
    '👻','💀','☠️','👽','👾','🤖','🎃','😺','😸','😹','😻','😼','😽','🙀','😿','😾',
  ]),
  _EmojiCat('👍', [
    '👍','👎','👌','🤌','🤏','✌️','🤞','🫰','🤟','🤘','🤙','👈','👉','👆','👇',
    '☝️','🫵','✋','🤚','🖐️','🖖','👋','🤝','🫱','🫲','🫳','🫴','🙏','💪','🦾',
    '🙌','👏','🤲','🫶','👐','✊','👊','🤛','🤜','✍️','💅','🤳','💃','🕺','👶',
    '🧒','👦','👧','🧑','👨','👩','🧔','👴','👵','🙇','💁','🙅','🙆','🙋','🤦',
    '🤷','👮','🕵️','💂','👷','🤴','👸','👰','🤵','🦸','🦹','🧙','🧚','🧛','🧜',
    '👣','👀','👁️','🧠','🫀','🫁','🦷','🦴','👅','👄','🫦','💋','🩸',
  ]),
  _EmojiCat('❤️', [
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','❤️‍🔥','❤️‍🩹','💔','❣️','💕','💞',
    '💓','💗','💖','💘','💝','💟','♥️','💌','⭐','🌟','✨','⚡','🔥','💥','💫',
    '💯','💢','💦','💨','🕳️','💬','💭','🗯️','♻️','✅','☑️','✔️','❌','❎','➕',
    '➖','➗','✖️','❓','❔','❗','❕','‼️','⁉️','〰️','🔝','🔙','🔚','🔛','🔜',
    '🎉','🎊','🎁','🎈','🎀','🏆','🥇','🥈','🥉','🏅','👑','💎','🔔','🔕',
  ]),
  _EmojiCat('🐶', [
    '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐻‍❄️','🐨','🐯','🦁','🐮','🐷','🐽',
    '🐸','🐵','🙈','🙉','🙊','🐒','🐔','🐧','🐦','🐤','🐣','🐥','🦆','🦅','🦉',
    '🦇','🐺','🐗','🐴','🦄','🐝','🪲','🐛','🦋','🐌','🐞','🐜','🪰','🦂','🕷️',
    '🐢','🐍','🦎','🦖','🐙','🦑','🦐','🦀','🐡','🐠','🐟','🐬','🐳','🐋','🦈',
    '🐊','🐅','🐆','🦓','🦍','🐘','🦏','🐪','🐫','🦒','🦘','🐃','🐂','🐄','🐎',
    '🐖','🐏','🐑','🐐','🦌','🐕','🐩','🐈','🐓','🦃','🦚','🦜','🕊️','🐇','🐿️',
    '🌵','🌲','🌳','🌴','🌱','🌿','🍀','🎍','🍃','🍂','🍁','🌾','💐','🌷','🌹',
    '🥀','🌺','🌸','🌼','🌻','🌞','🌝','🌚','🌍','🌎','🌏','⭐','🌙','☁️','⛅',
    '🌈','☀️','🌊','❄️','⛄','💧',
  ]),
  _EmojiCat('🍔', [
    '🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍',
    '🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️','🫑','🌽','🥕','🫒','🧄','🧅',
    '🥔','🍠','🥐','🥯','🍞','🥖','🧀','🥚','🍳','🧈','🥞','🧇','🥓','🥩','🍗',
    '🍖','🌭','🍔','🍟','🍕','🥪','🥙','🧆','🌮','🌯','🥗','🥘','🍝','🍜','🍲',
    '🍛','🍣','🍱','🥟','🍤','🍙','🍚','🍘','🍥','🥮','🍢','🍡','🍧','🍨','🍦',
    '🥧','🧁','🍰','🎂','🍮','🍭','🍬','🍫','🍿','🍩','🍪','🌰','🥜','🍯','🥛',
    '🍼','☕','🍵','🧃','🥤','🧋','🍶','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🧉','🍾',
  ]),
  _EmojiCat('⚽', [
    '⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🥏','🎱','🪀','🏓','🏸','🏒','🏑',
    '🥍','🏏','🥅','⛳','🪁','🎣','🤿','🥊','🥋','🎽','🛹','🛼','🛷','⛸️','🥌',
    '🎿','⛷️','🏂','🏋️','🤼','🤸','⛹️','🤺','🤾','🏌️','🏇','🧘','🏄','🏊','🤽',
    '🚣','🧗','🚵','🚴','🏆','🥇','🥈','🥉','🏅','🎖️','🏵️','🎗️','🎫','🎟️','🎪',
    '🤹','🎭','🩰','🎨','🎬','🎤','🎧','🎼','🎹','🥁','🎷','🎺','🎸','🪕','🎻',
    '🎲','♟️','🎯','🎳','🎮','🎰','🧩','🎨','📸','📷','🎥','📽️','📺','📻',
  ]),
  _EmojiCat('💡', [
    '⌚','📱','💻','⌨️','🖥️','🖨️','🖱️','💽','💾','💿','📀','📷','📸','📹','🎥',
    '📞','☎️','📟','📠','📺','📻','🎙️','⏰','⏱️','⏲️','🕰️','⌛','⏳','📡','🔋',
    '🔌','💡','🔦','🕯️','🪔','🧯','🛢️','💸','💵','💴','💶','💷','🪙','💰','💳',
    '💎','⚖️','🧰','🔧','🔨','⚒️','🛠️','⛏️','🔩','⚙️','🧱','⛓️','🧲','🔫','💣',
    '🧨','🔪','🗡️','⚔️','🛡️','🚬','⚰️','🪦','🏺','🔮','📿','🧿','💈','⚗️','🔭',
    '🔬','🕳️','🩹','🩺','💊','💉','🩸','🧬','🦠','🧫','🧪','🌡️','🧹','🧺','🧻',
    '🚽','🚰','🚿','🛁','🛀','🧼','🪒','🧴','🛎️','🔑','🗝️','🚪','🪑','🛋️','🛏️',
    '🖼️','🛍️','🛒','🎁','🎈','🎀','🎊','🎉','📚','📖','📕','📗','📘','📙','📓',
    '📔','📒','📃','📜','📄','📰','🗞️','📑','🔖','🏷️','✏️','✒️','🖋️','🖊️','🖌️',
    '🖍️','📝','💼','📁','📂','🗂️','📅','📆','🗒️','🗓️','📇','📈','📉','📊','📋',
    '📌','📍','📎','🖇️','📏','📐','✂️','🔒','🔓','🔏','🔐','✈️','🚗','🚕','🚌',
    '🚀','🛸','🚁','⛵','🚤','🏠','🏡','🏢','🏥','🏦','🏨','🏫','⛪','🕌','🗽','🗼',
  ]),
  _EmojiCat('🇷🇺', [
    '🏳️','🏴','🏁','🚩','🏳️‍🌈','🏳️‍⚧️','🇷🇺','🇺🇿','🇰🇿','🇰🇬','🇹🇯','🇹🇲',
    '🇺🇸','🇬🇧','🇩🇪','🇫🇷','🇮🇹','🇪🇸','🇵🇹','🇳🇱','🇧🇪','🇨🇭','🇦🇹','🇸🇪',
    '🇳🇴','🇩🇰','🇫🇮','🇵🇱','🇺🇦','🇨🇿','🇬🇷','🇹🇷','🇷🇴','🇭🇺','🇨🇳','🇯🇵',
    '🇰🇷','🇮🇳','🇵🇰','🇧🇩','🇮🇩','🇹🇭','🇻🇳','🇵🇭','🇲🇾','🇸🇬','🇸🇦','🇦🇪',
    '🇶🇦','🇮🇱','🇪🇬','🇮🇷','🇮🇶','🇧🇷','🇦🇷','🇲🇽','🇨🇦','🇦🇺','🇳🇿','🇿🇦',
  ]),
];

/// Telegram-style inline emoji panel: sits BELOW the text field like a
/// keyboard, so the message input stays visible while picking emoji.
class EmojiPanel extends StatefulWidget {
  final ValueChanged<String> onEmoji;
  final VoidCallback? onBackspace;
  final double height;
  const EmojiPanel(
      {super.key,
      required this.onEmoji,
      this.onBackspace,
      this.height = 280});
  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      height: widget.height,
      color: c.surface,
      child: Column(children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                itemCount: _cats.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => setState(() => _cat = i),
                  child: Container(
                    width: 42,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(
                        horizontal: 2, vertical: 6),
                    decoration: BoxDecoration(
                        color: _cat == i ? c.accent.withOpacity(0.18) : null,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(_cats[i].icon,
                        style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            ),
            if (widget.onBackspace != null)
              IconButton(
                icon: Icon(Icons.backspace_outlined, color: c.inkSoft),
                onPressed: widget.onBackspace,
              ),
          ]),
        ),
        Divider(height: 1, color: c.ink.withOpacity(0.06)),
        Expanded(
          child: GridView.count(
            crossAxisCount: 8,
            padding: const EdgeInsets.all(6),
            children: _cats[_cat]
                .emojis
                .map((e) => GestureDetector(
                      onTap: () => widget.onEmoji(e),
                      child: Center(
                          child:
                              Text(e, style: const TextStyle(fontSize: 26))),
                    ))
                .toList(),
          ),
        ),
      ]),
    );
  }
}

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

  static Future<List<String>> _loadRecents() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList('emoji_recent') ?? [];
  }

  static Future<void> _saveRecent(String e) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList('emoji_recent') ?? [];
    list.remove(e);
    list.insert(0, e);
    await p.setStringList('emoji_recent', list.take(24).toList());
  }

  Future<void> _show(BuildContext context) async {
    final c = context.k;
    int cat = -1; // -1 = Recents
    String query = '';
    final recents = await _loadRecents();
    if (recents.isEmpty) cat = 0;
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      // Light barrier so the content behind (story, comments) stays visible.
      barrierColor: Colors.black26,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Search across the keyword index (EN + RU).
          List<String> emojis;
          if (query.trim().isNotEmpty) {
            final q = query.trim().toLowerCase();
            emojis = _kw.entries
                .where((e) => e.value.contains(q))
                .map((e) => e.key)
                .toList();
          } else if (cat == -1) {
            emojis = recents;
          } else {
            emojis = _cats[cat].emojis;
          }
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: 330,
              child: Column(children: [
                const SizedBox(height: 8),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: c.ink.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2)),
                ),
                // Search field
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                  child: TextField(
                    onChanged: (v) => setSheet(() => query = v),
                    style: TextStyle(color: c.ink, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: ctx.t('emojiSearch'),
                      prefixIcon:
                          Icon(Icons.search_rounded, color: c.inkSoft, size: 20),
                      filled: true,
                      fillColor: c.surface2,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                if (query.trim().isEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        if (recents.isNotEmpty)
                          GestureDetector(
                            onTap: () => setSheet(() => cat = -1),
                            child: Container(
                              width: 46,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 2, vertical: 6),
                              decoration: BoxDecoration(
                                  color: cat == -1
                                      ? c.accent.withOpacity(0.18)
                                      : null,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.history_rounded,
                                  size: 22,
                                  color:
                                      cat == -1 ? c.accent : c.inkSoft),
                            ),
                          ),
                        ...List.generate(
                          _cats.length,
                          (i) => GestureDetector(
                            onTap: () => setSheet(() => cat = i),
                            child: Container(
                              width: 46,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 2, vertical: 6),
                              decoration: BoxDecoration(
                                  color: cat == i
                                      ? c.accent.withOpacity(0.18)
                                      : null,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text(_cats[i].icon,
                                  style: const TextStyle(fontSize: 22)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(height: 1, color: c.ink.withOpacity(0.06)),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 8,
                    padding: const EdgeInsets.all(6),
                    children: emojis
                        .map((e) => GestureDetector(
                              onTap: () {
                                _insert(e);
                                _saveRecent(e);
                                // Close right away so the reply field and the
                                // content behind are visible again.
                                Navigator.pop(sheetCtx);
                              },
                              child: Center(
                                  child: Text(e,
                                      style:
                                          const TextStyle(fontSize: 24))),
                            ))
                        .toList(),
                  ),
                ),
              ]),
            ),
          );
        },
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
