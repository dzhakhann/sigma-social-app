import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;
  bool _connected = false;
  final String _wsUrl = 'https://sigma-social-backend.onrender.com';

  Function(Map)? onMessageReceived;

  void connect(String userId) {
    if (_connected) return;
    socket = IO.io(
        _wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect()
            .build());

    socket.onConnect((_) {
      _connected = true;
      socket.emit('user_connect', {'userId': userId, 'username': 'User'});
    });

    socket.on('receive_message', (data) {
      onMessageReceived?.call(Map<String, dynamic>.from(data));
    });

    socket.onDisconnect((_) => _connected = false);
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
