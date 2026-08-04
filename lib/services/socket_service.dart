import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as IO;

/// App-wide socket connection. Broadcast streams (not a single callback
/// field) so MULTIPLE listeners can react to the same event — e.g. a
/// persistent app-level handler (writes to on-device chat history so read
/// receipts aren't lost when no chat screen is open) AND the currently-open
/// ChatDetailScreen (live UI update) both react to one 'messages_read' event
/// without clobbering each other's registration.
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  static const String _wsUrl = 'https://sigma-social-backend.onrender.com';

  bool _connected = false;
  String? _userId;

  final _messageCtrl = StreamController<Map>.broadcast();
  final _readCtrl = StreamController<Map>.broadcast();
  final _deliveredCtrl = StreamController<Map>.broadcast();
  final _chatPinCtrl = StreamController<Map>.broadcast();
  final _groupPinCtrl = StreamController<Map>.broadcast();
  final _groupMessageCtrl = StreamController<Map>.broadcast();
  final _notificationCtrl = StreamController<Map>.broadcast();
  final _groupSeenCtrl = StreamController<Map>.broadcast();
  final _groupReadCtrl = StreamController<Map>.broadcast();
  final _groupReactionCtrl = StreamController<Map>.broadcast();
  final _reactionCtrl = StreamController<Map>.broadcast();
  final _groupEditCtrl = StreamController<Map>.broadcast();

  /// New chat message delivered to us or the other participant.
  Stream<Map> get onMessage => _messageCtrl.stream;

  /// The other person OPENED the chat and read our messages (✓✓ in accent).
  Stream<Map> get onRead => _readCtrl.stream;

  /// The other phone picked our messages up off the queue — delivered, but
  /// not necessarily read (plain ✓✓). This used to be conflated with
  /// [onRead]: the chat LIST acks incoming messages in the background, so
  /// every delivered message immediately claimed to have been read.
  Stream<Map> get onDelivered => _deliveredCtrl.stream;

  /// A 1:1 chat's pinned message changed. `pinned_message` is null on unpin.
  Stream<Map> get onChatPin => _chatPinCtrl.stream;

  /// A group's pinned message changed. `pinned_message` is null on unpin.
  Stream<Map> get onGroupPin => _groupPinCtrl.stream;

  /// New group message delivered to us.
  Stream<Map> get onGroupMessage => _groupMessageCtrl.stream;

  /// Someone we follow published a post/story (or any other activity
  /// notification — like/comment/follow/repost) — pushed live instead of
  /// making the app poll for it.
  Stream<Map> get onNotification => _notificationCtrl.stream;

  /// A group member just acked (≈ saw) one of our group messages. There's no
  /// server-side history of this to re-query later (group_messages rows are
  /// deleted once every member has acked), so the running "seen by" list is
  /// built ENTIRELY from these live events, same as 1:1 read receipts.
  Stream<Map> get onGroupMessageSeen => _groupSeenCtrl.stream;

  /// Someone OPENED the group chat and read specific messages. Distinct from
  /// [onGroupMessageSeen], which only means their phone downloaded them.
  Stream<Map> get onGroupMessageRead => _groupReadCtrl.stream;

  /// A group message's reaction map changed (someone added/removed/changed
  /// their emoji reaction).
  Stream<Map> get onGroupMessageReaction => _groupReactionCtrl.stream;

  /// A 1:1 message's reaction map changed.
  Stream<Map> get onMessageReaction => _reactionCtrl.stream;

  /// A group message's text was edited by its author.
  Stream<Map> get onGroupMessageEdited => _groupEditCtrl.stream;

  /// Fired when someone completed a Sigma Nearby exchange with us — the other
  /// phone did the /nearby/connect call and the server pushed us the profile.
  /// Single-callback is fine here: only one Nearby screen is ever open.
  Function(Map)? onNearbyConnected;

  // Constructed + wired exactly once, on first access — `late final` with an
  // initializer guarantees the socket.on(...) handlers below are registered
  // a single time no matter how many screens call connect().
  late final IO.Socket socket = IO.io(
    _wsUrl,
    IO.OptionBuilder()
        .setTransports(['websocket', 'polling'])
        .disableAutoConnect()
        .build(),
  )
    ..onConnect((_) {
      _connected = true;
      final uid = _userId;
      if (uid != null)
        socket.emit('user_connect', {'userId': uid, 'username': 'User'});
    })
    ..onDisconnect((_) => _connected = false)
    ..on('receive_message',
        (data) => _messageCtrl.add(Map<String, dynamic>.from(data)))
    ..on('nearby_connected',
        (data) => onNearbyConnected?.call(Map<String, dynamic>.from(data)))
    ..on('messages_read',
        (data) => _readCtrl.add(Map<String, dynamic>.from(data)))
    ..on('messages_delivered',
        (data) => _deliveredCtrl.add(Map<String, dynamic>.from(data)))
    ..on('chat_pin',
        (data) => _chatPinCtrl.add(Map<String, dynamic>.from(data)))
    ..on('group_pin',
        (data) => _groupPinCtrl.add(Map<String, dynamic>.from(data)))
    ..on('receive_group_message',
        (data) => _groupMessageCtrl.add(Map<String, dynamic>.from(data)))
    ..on('notification',
        (data) => _notificationCtrl.add(Map<String, dynamic>.from(data)))
    ..on('group_message_read',
        (data) => _groupReadCtrl.add(Map<String, dynamic>.from(data)))
    ..on('group_message_seen',
        (data) => _groupSeenCtrl.add(Map<String, dynamic>.from(data)))
    ..on('group_message_reaction',
        (data) => _groupReactionCtrl.add(Map<String, dynamic>.from(data)))
    ..on('message_reaction',
        (data) => _reactionCtrl.add(Map<String, dynamic>.from(data)))
    ..on('group_message_edited',
        (data) => _groupEditCtrl.add(Map<String, dynamic>.from(data)));

  void connect(String userId) {
    _userId = userId;
    if (_connected) return;
    socket.connect();
  }

  void sendMessage(String chatId, String content, String userId) {
    socket.emit('send_message',
        {'chat_id': chatId, 'sender_id': userId, 'content': content});
  }

  void disconnect() {
    socket.disconnect();
    _connected = false;
  }
}
