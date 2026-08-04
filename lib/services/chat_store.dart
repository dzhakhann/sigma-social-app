import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device chat history (WhatsApp model). Messages live in per-chat JSON
/// files inside the app documents dir; the SERVER keeps a message row only
/// until this device confirms receipt (POST /messages/ack), then the row is
/// deleted — the database stores only the in-flight queue, never history.
///
/// Consequences (by design):
///  · история переживает переустановку через Android Auto Backup (Google);
///  · очистка данных приложения = история удалена;
///  · другой телефон видит список чатов, но истории пустые.
/// Removes rows sharing an `id`, keeping the LAST occurrence (the freshest —
/// later writes carry newer reactions/read state).
///
/// Duplicates are unavoidable in this design: ChatsScreen persists incoming
/// messages while the list is open, and ChatDetailScreen rewrites the whole file
/// from its own in-memory copy. Interleave those two and the same message lands
/// twice.
///
/// It isn't cosmetic. Each row becomes a `KeyedSubtree` with a GlobalKey looked
/// up BY ID, so a duplicate id means two widgets sharing one GlobalKey — Flutter
/// throws, that subtree fails to build, and everything attached to it dies,
/// including long-press. That presented as "the menu doesn't open on older
/// messages".
List dedupeById(List rows) {
  final byId = <String, dynamic>{};
  final order = <String>[];
  for (final r in rows) {
    final id = (r is Map ? r['id'] : null)?.toString();
    if (id == null) continue;
    if (!byId.containsKey(id)) order.add(id);
    byId[id] = r;
  }
  return order.map((id) => byId[id]!).toList();
}

class ChatStore {
  static Directory? _dir;

  static Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/chats');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  // path_provider has no web implementation at all — there's no filesystem to
  // hand back a Directory for. Without this branch every load()/save() on web
  // silently failed inside its own try/catch (load() always returning `[]`,
  // save() always no-op'ing), so — given the server only keeps an undelivered
  // queue, never permanent history — chat history didn't just fail to persist
  // on web, it was lost the moment a message got acked. localStorage (via
  // shared_preferences, which does have a web build) is this device's
  // equivalent of "the file IS the archive" there.
  static Future<String?> _webGet(String chatId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('chat_$chatId');
  }

  static Future<List<Map>> load(String chatId) async {
    try {
      if (kIsWeb) {
        final raw = await _webGet(chatId);
        if (raw == null) return [];
        return dedupeById((jsonDecode(raw) as List).map((e) => Map.from(e)).toList())
            .cast<Map>();
      }
      final f = File('${(await _root()).path}/$chatId.json');
      if (!f.existsSync()) return [];
      // Deduped on read too, so files already written by an older build with
      // duplicates in them are healed on first open instead of staying broken.
      return dedupeById(((jsonDecode(await f.readAsString())) as List)
              .map((e) => Map.from(e))
              .toList())
          .cast<Map>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String chatId, List messages) async {
    try {
      // Deduped here rather than at each call site: this is the one funnel
      // every writer passes through, so a duplicate can't survive a save no
      // matter which screen produced it.
      final rows = dedupeById(messages
          .whereType<Map>()
          .where((m) => m['_pending'] != true)
          .toList());

      // REFUSE to truncate an existing history to nothing.
      //
      // This is device-stored history — the file IS the archive, and the server
      // keeps only the undelivered queue, so an empty write is permanent data
      // loss with nothing to restore from.
      //
      // It happened routinely: the chat screens call save() from their socket
      // handlers unconditionally, and a seen/reaction event that arrives before
      // the local history has finished loading saves an empty in-memory list
      // over the real file. That's the "group history disappears after
      // restarting the app" bug.
      //
      // Deliberate wipes go through [clear], which deletes the file outright.
      if (kIsWeb) {
        final p = await SharedPreferences.getInstance();
        if (rows.isEmpty) {
          final existing = await _webGet(chatId);
          if (existing != null && existing.trim().isNotEmpty && existing.trim() != '[]') {
            return;
          }
        }
        await p.setString('chat_$chatId', jsonEncode(rows));
        return;
      }

      final f = File('${(await _root()).path}/$chatId.json');
      if (rows.isEmpty && f.existsSync()) {
        final existing = await f.readAsString();
        if (existing.trim().isNotEmpty && existing.trim() != '[]') return;
      }

      await f.writeAsString(jsonEncode(rows));
    } catch (_) {}
  }

  /// "Clear history" (Telegram-style) — wipes THIS device's local copy only.
  static Future<void> clear(String chatId) async {
    try {
      if (kIsWeb) {
        await (await SharedPreferences.getInstance()).remove('chat_$chatId');
        return;
      }
      final f = File('${(await _root()).path}/$chatId.json');
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
