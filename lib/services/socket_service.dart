import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  late IO.Socket socket;
  final String wsUrl = 'http://localhost:3000';

  void connect(String userId) {
    socket = IO.io(
        wsUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build());

    socket.onConnect((_) {
      print('✅ Connected to WebSocket');
      socket.emit('user_connect', {
        'userId': userId,
        'username': 'User',
      });
    });

    socket.on('receive_message', (data) {
      print('💬 New message: ${data['content']}');
    });

    socket.onDisconnect((_) => print('🔴 Disconnected'));
    socket.connect();
  }

  void sendMessage(String chatId, String content, String userId) {
    socket.emit('send_message', {
      'chat_id': chatId,
      'sender_id': userId,
      'content': content,
    });
  }

  void disconnect() {
    socket.disconnect();
  }
}
