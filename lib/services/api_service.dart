import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';

class ApiService {
  // ─── SESSION ────────────────────────────────────────────────────────────────
  // JWT issued by the server on login/register/recover. Attached to every
  // request so the server knows who is acting — the client no longer needs to
  // be trusted to send its own user id on writes.
  static String? _token;
  static void setToken(String? token) => _token = token;
  static void clearToken() => _token = null;
  static bool get isAuthed => _token != null;

  static Map<String, String> _headers({bool json = false}) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$kApiUrl$path'), headers: _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> _post(String path, Map body) async {
    final res = await http.post(Uri.parse('$kApiUrl$path'),
        headers: _headers(json: true), body: jsonEncode(body));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> _delete(String path) async {
    final res =
        await http.delete(Uri.parse('$kApiUrl$path'), headers: _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> _put(String path, Map body) async {
    final res = await http.put(Uri.parse('$kApiUrl$path'),
        headers: _headers(json: true), body: jsonEncode(body));
    return jsonDecode(res.body);
  }

  // ─── AUTH ─────────────────────────────────────────────────────────────────

  static Future<Map> register(String username, String password) =>
      _post('/auth/register', {
        'username': username,
        'password': password,
      });

  static Future<Map> login(String username, String password) =>
      _post('/auth/login', {'username': username, 'password': password});

  // Reset password using the recovery phrase — no email/phone needed.
  static Future<Map> recover(
          String username, String phrase, String newPassword) =>
      _post('/auth/recover', {
        'username': username,
        'phrase': phrase,
        'new_password': newPassword,
      });

  // ─── MEDIA ────────────────────────────────────────────────────────────────
  // Upload bytes through the server (which holds the Supabase key) and get back
  // a public URL. The client never touches the storage key.
  static Future<String?> uploadMedia(
    List<int> bytes, {
    String folder = 'upload',
    String ext = 'jpg',
    String contentType = 'image/jpeg',
    String? userId,
  }) async {
    final d = await _post('/upload', {
      'file_base64': base64Encode(bytes),
      'user_id': userId,
      'folder': folder,
      'ext': ext,
      'content_type': contentType,
    });
    return d['success'] == true ? d['url'] as String? : null;
  }

  // ─── USERS ────────────────────────────────────────────────────────────────

  static Future<Map> getUser(String userId) => _get('/users/$userId');

  static Future<List> getUsers() async {
    final d = await _get('/users');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> updateUser(String userId, Map fields) =>
      _post('/users/$userId/update', fields);

  static Future<Map> follow(String userId, String targetId) =>
      _post('/users/$userId/follow/$targetId', {});

  static Future<Map> unfollow(String userId, String targetId) =>
      _post('/users/$userId/unfollow/$targetId', {});

  static Future<bool> isFollowing(String userId, String targetId) async {
    final d = await _get('/users/$userId/following/$targetId');
    return d['isFollowing'] == true;
  }

  // ─── POSTS ────────────────────────────────────────────────────────────────

  static Future<List> getPosts(String userId) async {
    final d = await _get('/posts?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<List> getFollowingPosts(String userId) async {
    final d = await _get('/posts/following?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> createPost(String userId, String content,
      {String? imageUrl}) =>
      _post('/posts', {
        'user_id': userId,
        'content': content,
        if (imageUrl != null) 'image_url': imageUrl,
      });

  static Future<Map> likePost(String postId, String userId) =>
      _post('/posts/$postId/like', {'user_id': userId});

  // ─── COMMENTS ─────────────────────────────────────────────────────────────

  static Future<List> getComments(String postId) async {
    final d = await _get('/posts/$postId/comments');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> addComment(
          String postId, String userId, String content) =>
      _post('/posts/$postId/comments',
          {'user_id': userId, 'content': content});

  static Future<Map> deleteComment(String commentId) =>
      _delete('/comments/$commentId');

  // ─── STORIES ──────────────────────────────────────────────────────────────

  static Future<List> getStories() async {
    final d = await _get('/stories');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> uploadStory(String userId, String base64Image) =>
      _post('/stories/upload',
          {'user_id': userId, 'image_base64': base64Image});

  static Future<Map> deleteStory(String storyId) =>
      _delete('/stories/$storyId');

  // ─── CHATS ────────────────────────────────────────────────────────────────

  static Future<List> getChats(String userId) async {
    final d = await _get('/chats?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> getOrCreateChat(String user1Id, String user2Id) =>
      _post('/chats/get-or-create',
          {'user1_id': user1Id, 'user2_id': user2Id});

  // ─── MESSAGES ─────────────────────────────────────────────────────────────

  static Future<List> getMessages(String chatId) async {
    final d = await _get('/messages/$chatId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> sendMessage(
    String chatId,
    String senderId,
    String content, {
    String? mediaUrl,
    String messageType = 'text',
  }) =>
      _post('/messages', {
        'chat_id': chatId,
        'sender_id': senderId,
        'content': content,
        'message_type': messageType,
        if (mediaUrl != null) 'media_url': mediaUrl,
      });

  static Future<Map> deleteMessage(String messageId) =>
      _delete('/messages/$messageId');

  static Future<Map> editMessage(String messageId, String content) =>
      _put('/messages/$messageId', {'content': content});

  // ─── NOTIFICATIONS ────────────────────────────────────────────────────────

  static Future<List> getNotifications(String userId) async {
    final d = await _get('/notifications?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> markNotificationRead(String notifId) =>
      _post('/notifications/$notifId/read', {});

  static Future<Map> markAllNotificationsRead(String userId) =>
      _post('/notifications/read-all', {'user_id': userId});

  // ─── SEARCH ───────────────────────────────────────────────────────────────

  static Future<List> searchUsers(String query) async {
    if (query.isEmpty) return [];
    final d =
        await _get('/search/users?q=${Uri.encodeComponent(query)}');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  // ─── REELS (kept for backward compat) ─────────────────────────────────────

  static Future<List> getReels(String userId) async {
    final d = await _get('/reels?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> likeReel(String reelId, String userId) =>
      _post('/reels/$reelId/like', {'user_id': userId});

  static Future<Map> createReel(
          String userId, String videoUrl, String caption) =>
      _post('/reels',
          {'user_id': userId, 'video_url': videoUrl, 'caption': caption});

  static Future<Map> uploadReelVideo(
      String userId, List<int> bytes, String filename) async {
    final url = await uploadMedia(bytes,
        folder: 'reel', ext: 'mp4', contentType: 'video/mp4', userId: userId);
    if (url != null) return {'success': true, 'url': url};
    return {'success': false, 'error': 'Upload failed'};
  }
}
