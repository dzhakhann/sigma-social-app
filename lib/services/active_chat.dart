/// Which conversation is on screen right now.
///
/// Exists so an incoming-message banner isn't shown for the chat the user is
/// already reading — announcing a message that's visibly arriving in front of
/// them is pure noise, and it's what makes an in-app banner feel broken.
///
/// A plain static rather than a provider: exactly one chat can be open at a
/// time, and both the chat screens and MainScreen need to agree on which.
class ActiveChat {
  ActiveChat._();

  static String? _chatId;
  static String? _groupId;

  static void openChat(String? id) {
    _chatId = id;
    _groupId = null;
  }

  static void openGroup(String? id) {
    _groupId = id;
    _chatId = null;
  }

  /// Call from dispose. Guarded by id so a screen being torn down AFTER its
  /// replacement was already registered can't clear the newer one.
  static void close(String? id) {
    if (_chatId == id) _chatId = null;
    if (_groupId == id) _groupId = null;
  }

  /// True when this notification payload refers to the open conversation.
  static bool matches(Map payload) {
    final chat = payload['chat_id']?.toString();
    final group = payload['group_id']?.toString();
    if (group != null && group.isNotEmpty) return group == _groupId;
    if (chat != null && chat.isNotEmpty) return chat == _chatId;
    return false;
  }
}
