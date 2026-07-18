import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../theme/brutal_theme.dart' show appConfig;

class ApiService {
  // ─── SESSION ────────────────────────────────────────────────────────────────
  // JWT issued by the server on login/register/recover. Attached to every
  // request so the server knows who is acting — the client no longer needs to
  // be trusted to send its own user id on writes.
  static String? _token;
  static void setToken(String? token) => _token = token;

  /// Read-only token access for services that talk to the API directly
  /// (the background story publisher uses dio for upload progress).
  static String? get token => _token;
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
      {String? imageUrl, Map? music}) =>
      _post('/posts', {
        'user_id': userId,
        'content': content,
        if (imageUrl != null) 'image_url': imageUrl,
        // Only a Rhythm catalog reference — audio is never uploaded.
        if (music != null) 'music': music,
      });

  static Future<Map> likePost(String postId, String userId) =>
      _post('/posts/$postId/like', {'user_id': userId});

  static Future<Map> deletePost(String postId) => _delete('/posts/$postId');

  // A user's own posts (incl. reposts) — for the profile.
  static Future<List> getUserPosts(String targetId, String viewerId) async {
    final d = await _get('/users/$targetId/posts?userId=$viewerId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  // A single post by id — for opening a post from a notification.
  static Future<Map?> getPost(String postId, String viewerId) async {
    final d = await _get('/posts/$postId?userId=$viewerId');
    return d['success'] == true ? (d['data'] as Map?) : null;
  }

  // Repost: server creates the repost row + notifies followers.
  static Future<Map> repostPost(String postId) =>
      _post('/posts/$postId/repost', {});

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

  static Future<Map> editComment(String commentId, String content) =>
      _put('/comments/$commentId', {'content': content});

  // ─── STORIES ──────────────────────────────────────────────────────────────

  static Future<List> getStories() async {
    final d = await _get('/stories');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> uploadStory(String userId, String base64Image,
      {List<Map> links = const []}) async {
    if (links.isEmpty) {
      return _post('/stories/upload',
          {'user_id': userId, 'image_base64': base64Image});
    }
    // Link stickers have to be attached to the media URL, and that URL only
    // exists after the file is stored — so upload first, then create the story
    // once. (Posting twice would leave two stories in the feed.)
    final url = await uploadMedia(base64Decode(base64Image),
        folder: 'story', ext: 'jpg', contentType: 'image/jpeg', userId: userId);
    if (url == null) return {'success': false, 'error': 'Upload failed'};
    return _post('/stories/upload',
        {'user_id': userId, 'media_url': packStoryLinks(url, links)});
  }

  /// Creates a story record from an already-uploaded media URL (used by the
  /// background publisher, which uploads the file itself for progress).
  static Future<Map> createStoryFromUrl(String userId, String mediaUrl) =>
      _post('/stories/upload', {'user_id': userId, 'media_url': mediaUrl});

  /// Publish a VIDEO story. The clip is uploaded as a file first (base64 JSON
  /// can't carry 60s of video), then only its URL is stored — reusing the same
  /// `image_url` field, so nothing new is added to the database.
  static Future<Map> uploadVideoStory(String userId, List<int> bytes,
      {List<Map> links = const []}) async {
    final url = await uploadMedia(bytes,
        folder: 'story', ext: 'mp4', contentType: 'video/mp4', userId: userId);
    if (url == null) return {'success': false, 'error': 'Upload failed'};
    return _post('/stories/upload',
        {'user_id': userId, 'media_url': packStoryLinks(url, links)});
  }

  /// A story is a video when its media URL points at a clip.
  static bool isVideoStory(String url) {
    final u = url.toLowerCase().split('#').first.split('?').first;
    return u.endsWith('.mp4') || u.endsWith('.mov') || u.endsWith('.webm');
  }

  // ─── Story link stickers ───────────────────────────────────────────────────
  // Tappable links can't be baked into the picture — they'd just be pixels. We
  // keep them as data in the media URL's #fragment: fragments are client-side
  // only (never sent to the server), so the image/video still loads normally
  // and the database needs no new column.

  /// Packs story extras onto the media URL: link stickers and/or ONE music
  /// track (only its Rhythm stream link + fragment — never an audio copy).
  static String packStoryExtras(String mediaUrl,
      {List<Map> links = const [], Map? music}) {
    final base = mediaUrl.split('#').first;
    if (links.isEmpty && music == null) return base;
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      if (links.isNotEmpty) 'l': links,
      if (music != null) 'm': music,
    })));
    return '$base#s2=$payload';
  }

  /// Back-compat wrapper (older call sites pass links only).
  static String packStoryLinks(String mediaUrl, List<Map> links) =>
      packStoryExtras(mediaUrl, links: links);

  static Map<String, dynamic> _storyExtras(String mediaUrl) {
    final i2 = mediaUrl.indexOf('#s2=');
    if (i2 >= 0) {
      try {
        final json = utf8.decode(base64Url.decode(mediaUrl.substring(i2 + 4)));
        return Map<String, dynamic>.from(jsonDecode(json));
      } catch (_) {
        return const {};
      }
    }
    // Legacy fragment: links-only list.
    final i = mediaUrl.indexOf('#lnk=');
    if (i >= 0) {
      try {
        final json = utf8.decode(base64Url.decode(mediaUrl.substring(i + 5)));
        return {'l': jsonDecode(json)};
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  /// Reads link stickers back out of a story's media URL.
  static List<Map> unpackStoryLinks(String mediaUrl) =>
      ((_storyExtras(mediaUrl)['l'] as List?) ?? const [])
          .map((e) => Map.from(e))
          .toList();

  /// The story's music: {url, title, artist, art, start, len, x, y, scale}.
  static Map? unpackStoryMusic(String mediaUrl) {
    final m = _storyExtras(mediaUrl)['m'];
    return m == null ? null : Map.from(m);
  }

  /// The URL to actually fetch — without our fragment.
  static String storyMediaUrl(String url) => url.split('#').first;

  static Future<Map> deleteStory(String storyId) =>
      _delete('/stories/$storyId');

  // All of a user's stories incl. expired — for the profile History archive.
  static Future<List> getUserStories(String userId) async {
    final d = await _get('/stories/user/$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

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

  static Future<List> getTrendingPosts(String userId) async {
    final d = await _get('/posts/trending?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<List> searchPosts(String query, String userId) async {
    if (query.isEmpty) return [];
    final d = await _get(
        '/search/posts?q=${Uri.encodeComponent(query)}&userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  // ─── CHANNELS (content bots you can subscribe to) ──────────────────────────
  static Future<List> getChannels(String userId) async {
    final d = await _get('/channels?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  // ─── GOALS (yearly goals + Wrapped) ────────────────────────────────────────
  static Future<List> getGoals(String userId, {int? year}) async {
    final y = year != null ? '&year=$year' : '';
    final d = await _get('/goals?userId=$userId$y');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> createGoal(String title, String category, int year,
          {String note = ''}) =>
      _post('/goals', {
        'title': title,
        'category': category,
        'year': year,
        'note': note,
      });

  static Future<Map> updateGoal(String id, Map fields) =>
      _post('/goals/$id/update', fields);

  static Future<Map> deleteGoal(String id) => _delete('/goals/$id');

  static Future<Map> getWrapped(String userId, {int? year}) async {
    final y = year != null ? '&year=$year' : '';
    final d = await _get('/goals/wrapped?userId=$userId$y');
    return d['success'] == true ? (d['data'] ?? {}) : {};
  }

  // Self-service account deletion (Google Play requirement).
  static Future<Map> deleteAccount() => _delete('/account');

  // ─── STORY STATS + PROFILE ANALYTICS ─────────────────────────────────────
  static Future<Map> viewStoryStat(String storyId) =>
      _post('/stories/$storyId/view', {});
  static Future<Map> likeStoryStat(String storyId) =>
      _post('/stories/$storyId/like-stat', {});
  static Future<Map> replyStoryStat(String storyId) =>
      _post('/stories/$storyId/reply-stat', {});
  static Future<Map> storyStats(String storyId) async {
    final d = await _getSafe('/stories/$storyId/stats');
    return d['success'] == true ? d : {};
  }

  // ─── HOME CARDS ────────────────────────────────────────────────────────────
  static Future<List<Map>> feedActivity() async {
    final d = await _getSafe('/feed/activity');
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List).map((e) => Map.from(e)).toList();
  }

  static Future<String> aiWeek() async {
    final d = await _getSafe('/ai/week?lang=${appConfig.value.lang}');
    return (d['text'] ?? '').toString();
  }

  static Future<Map> dailyReward() => _post('/daily-reward', {});

  // ─── MODERATION: report / block / hide / verification ─────────────────────
  static Future<Map> report(String targetType, String targetId,
          {String reason = 'other', String note = '', String link = ''}) =>
      _post('/reports', {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'note': note,
        'link': link,
      });

  static Future<Map> userByUsername(String username) async {
    final d = await _getSafe('/users/by-username/$username');
    return d['success'] == true ? (d['data'] ?? {}) : {};
  }

  static Future<Map> blockUser(String id) => _post('/block/$id', {});
  static Future<Map> unblockUser(String id) => _delete('/block/$id');
  static Future<Map> hideUser(String id) => _post('/hide/$id', {});
  static Future<Map> blockStatus(String id) async {
    final d = await _getSafe('/block/status/$id');
    return d['success'] == true ? d : {};
  }

  static Future<Map> applyVerification(
          {String email = '', String wiki = '', String info = ''}) =>
      _post('/verification', {'email': email, 'wiki': wiki, 'info': info});

  // "Газета" — one mixed stream: articles + YouTube news videos, per language.
  static Future<List<Map>> news() async {
    final d = await _getSafe('/news?lang=${appConfig.value.lang}');
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List).map((e) => Map.from(e)).toList();
  }

  static Future<Map> visitProfile(String userId) =>
      _post('/users/$userId/visit', {});
  static Future<Map> myAnalytics() async {
    final d = await _getSafe('/me/analytics');
    return d['success'] == true ? (d['data'] ?? {}) : {};
  }

  // ─── AI (Gemini via backend) ───────────────────────────────────────────────
  // messages: [{'role':'user'|'model','text':'...'}]
  static Future<String> aiChat(List<Map<String, String>> messages) async {
    final d = await _post('/ai/chat',
        {'messages': messages, 'lang': appConfig.value.lang});
    return (d['reply'] ??
            (appConfig.value.lang == 'ru' ? 'ИИ недоступен.' : 'AI is unavailable.'))
        .toString();
  }

  static Future<String> aiRecommend() async {
    final d = await _get('/ai/recommend?lang=${appConfig.value.lang}');
    return (d['text'] ?? '').toString();
  }

  // Horoscope for the user's zodiac sign (computed from their birthday).
  static Future<Map> horoscope() async {
    final d = await _getSafe('/ai/horoscope?lang=${appConfig.value.lang}');
    return d['success'] == true ? d : {};
  }

  // ─── PODCASTS (via our server proxy; nothing stored — pure pass-through) ────
  // A short timeout so the UI never hangs if the server is cold/unreachable.
  static Future<Map<String, dynamic>> _getSafe(String path,
      {int timeoutSec = 25}) async {
    try {
      final res = await http
          .get(Uri.parse('$kApiUrl$path'), headers: _headers())
          .timeout(Duration(seconds: timeoutSec));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'success': false};
    }
  }

  static Future<List<Map>> searchPodcasts(String term) async {
    final d =
        await _getSafe('/podcast/search?term=${Uri.encodeQueryComponent(term)}');
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List).map((e) => Map.from(e)).toList();
  }

  static Future<List<Map>> fetchEpisodes(String feedUrl) async {
    final d = await _getSafe(
        '/podcast/episodes?feed=${Uri.encodeQueryComponent(feedUrl)}');
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List).map((e) => Map.from(e)).toList();
  }

  // ─── AUDIOBOOKS (LibriVox — public domain, via backend proxy) ─────────────
  static Future<List<Map>> searchAudiobooks(String term,
      {String genre = '', String language = ''}) async {
    var q = '/audiobooks/search?term=${Uri.encodeQueryComponent(term)}';
    if (genre.isNotEmpty) q += '&genre=${Uri.encodeQueryComponent(genre)}';
    if (language.isNotEmpty) {
      q += '&language=${Uri.encodeQueryComponent(language)}';
    }
    final d = await _getSafe(q);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List).map((e) => Map.from(e)).toList();
  }

  // ─── MUSIC (Audius — free legal streaming API, commercial use allowed) ────
  static const String _audius = 'https://discoveryprovider.audius.co/v1';
  static const String _audiusApp = 'app_name=sigmacta';

  static Map _audiusTrack(Map t) => {
        'title': t['title'] ?? 'Track',
        'showTitle': (t['user']?['name'] ?? '').toString(),
        'artwork': (t['artwork']?['480x480'] ??
                t['artwork']?['150x150'] ??
                '')
            .toString(),
        'audio': '$_audius/tracks/${t['id']}/stream?$_audiusApp',
        'duration': t['duration']?.toString() ?? '',
        'kind': 'music', // distinguishes music from podcasts/books locally
      };

  static Future<List<Map>> musicTrending({String genre = ''}) async {
    try {
      final g = genre.isNotEmpty
          ? '&genre=${Uri.encodeQueryComponent(genre)}'
          : '';
      final r = await http
          .get(Uri.parse('$_audius/tracks/trending?$_audiusApp$g'))
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body);
      return ((j['data'] ?? []) as List)
          .map((t) => _audiusTrack(Map.from(t)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map>> musicSearch(String q) async {
    try {
      final r = await http
          .get(Uri.parse(
              '$_audius/tracks/search?query=${Uri.encodeQueryComponent(q)}&$_audiusApp'))
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body);
      return ((j['data'] ?? []) as List)
          .map((t) => _audiusTrack(Map.from(t)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── GIFs (Tenor via backend) ──────────────────────────────────────────────
  static Future<List> searchGifs(String query) async {
    final d = await _get('/gifs?q=${Uri.encodeComponent(query)}');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  // ─── Link preview (Open Graph unfurl) ──────────────────────────────────────
  static final Map<String, Map> _linkCache = {};
  static Future<Map> linkPreview(String url) async {
    if (_linkCache.containsKey(url)) return _linkCache[url]!;
    final d = await _get('/link-preview?url=${Uri.encodeComponent(url)}');
    final data = d['success'] == true ? (d['data'] ?? {}) : {};
    if (data is Map && (data['title'] != null || data['image'] != null)) {
      _linkCache[url] = Map<String, dynamic>.from(data);
    }
    return _linkCache[url] ?? {};
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

  // ─── ADMIN ──────────────────────────────────────────────────────────────────
  static Future<Map> adminStats() => _get('/admin/stats');

  static Future<List> adminUsers() async {
    final d = await _get('/admin/users');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> adminDeleteUser(String id) => _delete('/admin/users/$id');

  static Future<Map> adminToggleAdmin(String id) =>
      _post('/admin/users/$id/toggle-admin', {});

  static Future<List> adminPosts() async {
    final d = await _get('/admin/posts');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> adminDeletePost(String id) => _delete('/admin/posts/$id');
}
