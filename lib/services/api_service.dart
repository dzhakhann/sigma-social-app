import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../l10n/app_strings.dart' show S;
import '../theme/brutal_theme.dart' show appConfig;

class ApiService {
  /// Parses a timestamp coming from the backend (Postgres via Supabase),
  /// which serialises `timestamptz` columns WITHOUT a 'Z'/offset suffix
  /// (e.g. "2026-07-22T14:00:39.370143") even though the value is always UTC.
  /// Bare `DateTime.parse` treats a suffix-less string as LOCAL time, which
  /// silently shifted every "time ago" / online-status / read-receipt
  /// computation in the app by the device's UTC offset. Always use this
  /// instead of `DateTime.parse` for any `created_at`/`last_seen`/etc. field
  /// that came from the API.
  static DateTime parseServerTime(String raw) {
    final s = raw.trim();
    final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
    return DateTime.parse(hasZone ? s : '${s}Z').toLocal();
  }

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

  /// Fire-and-forget device/app telemetry for the admin CRM panel — see
  /// DeviceInfoService, called once right after login/register.
  static Future<void> sendSessionInfo({
    required String deviceModel,
    required String osVersion,
    required String appVersion,
    required String platform,
  }) async {
    try {
      await _post('/session-info', {
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'platform': platform,
      });
    } catch (_) {}
  }

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
          {String? imageUrl, Map? music, List<String>? mediaUrls}) =>
      _post('/posts', {
        'user_id': userId,
        'content': content,
        if (imageUrl != null) 'image_url': imageUrl,
        // Full photo carousel (Instagram-style) — image_url above stays the
        // first photo for any older code that only reads a single image.
        if (mediaUrls != null && mediaUrls.isNotEmpty) 'media_urls': mediaUrls,
        // Only a Rhythm catalog reference — audio is never uploaded.
        if (music != null) 'music': music,
      });

  static Future<Map> likePost(String postId, String userId) =>
      _post('/posts/$postId/like', {'user_id': userId});

  static Future<Map> deletePost(String postId) => _delete('/posts/$postId');

  static Future<Map> editPost(String postId, String content) =>
      _put('/posts/$postId', {'content': content});

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

  static Future<Map> addComment(String postId, String userId, String content) =>
      _post('/posts/$postId/comments', {'user_id': userId, 'content': content});

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
      return _post(
          '/stories/upload', {'user_id': userId, 'image_base64': base64Image});
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

  /// Packs story extras onto the media URL: link stickers, GIF stickers (kept
  /// live so they keep ANIMATING in the viewer — baked pixels can't) and/or
  /// ONE music track (only its Rhythm stream link + fragment — never audio).
  static String packStoryExtras(String mediaUrl,
      {List<Map> links = const [], Map? music, List<Map> gifs = const []}) {
    final base = mediaUrl.split('#').first;
    if (links.isEmpty && music == null && gifs.isEmpty) return base;
    final payload = base64Url.encode(utf8.encode(jsonEncode({
      if (links.isNotEmpty) 'l': links,
      if (music != null) 'm': music,
      if (gifs.isNotEmpty) 'g': gifs,
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

  /// The story's music: {url, title, artist, art, start, len, x, y, scale,
  /// style, rot, color}.
  static Map? unpackStoryMusic(String mediaUrl) {
    final m = _storyExtras(mediaUrl)['m'];
    return m == null ? null : Map.from(m);
  }

  /// Animated GIF stickers: [{url, x, y, scale, rot}].
  static List<Map> unpackStoryGifs(String mediaUrl) =>
      ((_storyExtras(mediaUrl)['g'] as List?) ?? const [])
          .map((e) => Map.from(e))
          .toList();

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
      _post('/chats/get-or-create', {'user1_id': user1Id, 'user2_id': user2Id});

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
    Map? replyTo,
    String? forwardedFrom,
  }) =>
      _post('/messages', {
        'chat_id': chatId,
        'sender_id': senderId,
        'content': content,
        'message_type': messageType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyTo != null) 'reply_to': replyTo,
        if (forwardedFrom != null) 'forwarded_from': forwardedFrom,
      });

  /// Confirms receipt: the server deletes the acked rows (device-stored
  /// history — the DB only holds messages not yet delivered).
  static Future<void> ackMessages(String chatId, List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _post('/messages/ack', {'chat_id': chatId, 'ids': ids});
    } catch (_) {}
  }

  static Future<Map> deleteMessage(String messageId) =>
      _delete('/messages/$messageId');

  static Future<Map> editMessage(String messageId, String content) =>
      _put('/messages/$messageId', {'content': content});

  static Future<Map> reactToMessage(String messageId, String emoji) =>
      _post('/messages/$messageId/react', {'emoji': emoji});

  /// Refreshes reactions/read-status for messages already in the local
  /// cache — catches up on anything that changed while this chat wasn't
  /// open to receive the live socket event. Best-effort: a failure just
  /// means the cache stays as-is until the next successful sync.
  static Future<Map<String, Map>> syncMessages(List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final d = await _post('/messages/sync', {'ids': ids});
      if (d['success'] != true) return {};
      return (d['data'] as Map)
          .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)));
    } catch (_) {
      return {};
    }
  }

  /// A shared /story/<id> link. Returns `{stories: [...], index: n}` — the
  /// author's whole current set plus where the linked one sits, because the
  /// viewer is a pager and a single story with no siblings can't be swiped.
  static Future<Map> storyById(String id) async {
    try {
      final d = await _get('/stories/$id');
      return d['success'] == true ? (d['data'] as Map? ?? {}) : {};
    } catch (_) {
      return {};
    }
  }

  // ─── GROUP READ RECEIPTS ──────────────────────────────────────────────────
  // Distinct from ack: ack = this phone downloaded it, read = this person
  // opened the chat. See migrations/group_message_reads.sql.

  static Future<void> markGroupRead(String groupId, List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _post('/groups/$groupId/messages/read', {'ids': ids});
    } catch (_) {}
  }

  /// `{read: [...], unread: [...]}` — both sides, so the client never has to
  /// infer "hasn't read" by subtracting a separately-fetched member list.
  static Future<Map> groupMessageReads(String groupId, String messageId) async {
    try {
      final d = await _get('/groups/$groupId/messages/$messageId/reads');
      return d['success'] == true ? (d['data'] as Map? ?? {}) : {};
    } catch (_) {
      return {};
    }
  }

  // ─── BILLING ──────────────────────────────────────────────────────────────

  /// Whether the server can verify a purchase at all. Asked BEFORE showing a
  /// Buy button — see the endpoint's comment for why offering one without this
  /// means charging a user for nothing.
  static Future<bool> billingAvailable() async {
    try {
      final d = await _get('/billing/status');
      return d['success'] == true && d['data']?['available'] == true;
    } catch (_) {
      // Unreachable server → assume unavailable. Failing closed is the only
      // safe default when the downside is an unverifiable charge.
      return false;
    }
  }

  /// Hands a Play purchase token to the server, which verifies it against the
  /// Play Developer API and grants Pro. The client never decides entitlement.
  static Future<Map> verifyPurchase({
    required String purchaseToken,
    required String productId,
  }) async {
    try {
      return await _post('/billing/verify', {
        'purchase_token': purchaseToken,
        'product_id': productId,
      });
    } catch (_) {
      return {'success': false, 'error': 'network'};
    }
  }

  // ─── PRO BADGE ────────────────────────────────────────────────────────────

  /// Sets (or clears, with null) the GIF shown instead of the "PRO" chip.
  /// Server rejects non-Giphy URLs and non-Pro accounts.
  static Future<Map> setProBadge(String? url) async {
    try {
      return await _put('/users/me/pro-badge', {'url': url});
    } catch (_) {
      return {'success': false, 'error': 'network'};
    }
  }

  // ─── PINNED MESSAGES ──────────────────────────────────────────────────────
  // Pass `message: null` to unpin — one endpoint handles both directions.
  // The server stores a trimmed snapshot, not a reference, because the message
  // row itself is deleted once delivered (device-stored history).

  static Future<Map?> pinChatMessage(String chatId, Map? message) async {
    try {
      final d = await _put('/chats/$chatId/pin', {'message': message});
      return d['success'] == true ? (d['data'] as Map?) : null;
    } catch (_) {
      return null;
    }
  }

  /// Groups are admin-only; a non-admin gets `error: 'admin_only'`.
  static Future<Map> pinGroupMessage(String groupId, Map? message) async {
    try {
      return await _put('/groups/$groupId/pin', {'message': message});
    } catch (_) {
      return {'success': false, 'error': 'network'};
    }
  }

  // ─── PROMO CODES ──────────────────────────────────────────────────────────

  /// Redeems a promo code for a Pro subscription. On failure `error` is a
  /// stable machine-readable reason (`not_found`, `expired`, `exhausted`,
  /// `already_used`, `inactive`) so the UI can localize it.
  static Future<Map> redeemPromo(String code) async {
    try {
      return await _post('/promo/redeem', {'code': code});
    } catch (_) {
      return {'success': false, 'error': 'network'};
    }
  }

  // ─── NOTIFICATIONS ────────────────────────────────────────────────────────

  static Future<List> getNotifications(String userId) async {
    final d = await _get('/notifications?userId=$userId');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> markNotificationRead(String notifId) =>
      _post('/notifications/$notifId/read', {});

  static Future<Map> markAllNotificationsRead(String userId) =>
      _post('/notifications/read-all', {'user_id': userId});

  static Future<Map> saveFcmToken(String token) =>
      _post('/users/fcm-token', {'token': token});

  // ─── SEARCH ───────────────────────────────────────────────────────────────

  static Future<List> searchUsers(String query) async {
    if (query.isEmpty) return [];
    final d = await _get('/search/users?q=${Uri.encodeComponent(query)}');
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

  // ─── SIGMAFIT (bundled exercise circuits, only a tiny result row server-side) ─
  static Future<Map> logWorkout(String routineId, int durationSeconds) => _post(
      '/workouts',
      {'routine_id': routineId, 'duration_seconds': durationSeconds});

  // ─── ОБЗОР: exact-handle YouTube channel + cached regional trending ────────
  /// Videos for a search query: the matching channel's own recent uploads if
  /// the query IS a YouTube handle, otherwise a normal keyword video search
  /// (the server decides — see /api/youtube/channel). Scraping + a videos.list
  /// batch can take a few seconds, hence the longer timeout than the old
  /// handle-only lookup had.
  static Future<List> getYoutubeChannelVideos(String handle) async {
    final d = await _getSafe(
        '/youtube/channel?handle=${Uri.encodeComponent(handle)}',
        timeoutSec: 25);
    if (d['success'] != true) return [];
    final data = d['data'] ?? {};
    return (data['found'] == true) ? (data['videos'] ?? []) : [];
  }

  static Future<List> getYoutubeTrending() async {
    final region = appConfig.value.lang == 'ru' ? 'ru' : 'us';
    final d =
        await _getSafe('/youtube/trending?region=$region', timeoutSec: 15);
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  // ─── DUELS (goal races between two friends) ────────────────────────────────
  static Future<List> getDuels() async {
    final d = await _get('/duels');
    return d['success'] == true ? (d['data'] ?? []) : [];
  }

  static Future<Map> createDuel(
          String title, String category, String opponentId) =>
      _post('/duels',
          {'title': title, 'category': category, 'opponent_id': opponentId});

  static Future<Map> respondDuel(String id, bool accept) =>
      _post('/duels/$id/respond', {'accept': accept});

  static Future<Map> updateDuelProgress(String id, int progress) =>
      _post('/duels/$id/progress', {'progress': progress});

  static Future<Map> deleteDuel(String id) => _delete('/duels/$id');

  // Self-service account deletion (Google Play requirement).
  static Future<Map> deleteAccount() => _delete('/account');

  // ─── NOTES (Instagram-style: 24h text note, mutual follows only) ──────────
  static Future<List<Map>> getNotes() async {
    final d = await _getSafe('/notes', timeoutSec: 15);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<bool> postNote(String text) async {
    try {
      final d = await _post('/notes', {'text': text});
      return d['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> deleteNote() async {
    try {
      await _delete('/notes');
    } catch (_) {}
  }

  // ─── GROUPS (Telegram-style open/closed group chats) ──────────────────────
  static Future<Map> createGroup(String name,
          {String description = '', bool isOpen = false, String? avatarUrl}) =>
      _post('/groups', {
        'name': name,
        'description': description,
        'is_open': isOpen,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      });

  static Future<List<Map>> getGroups() async {
    final d = await _getSafe('/groups', timeoutSec: 20);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Map?> getGroup(String id) async {
    final d = await _getSafe('/groups/$id', timeoutSec: 20);
    if (d['success'] != true) return null;
    return Map<String, dynamic>.from(d['data']);
  }

  static Future<Map> updateGroup(String id,
          {String? name, String? description, String? avatarUrl}) =>
      _put('/groups/$id', {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      });

  static Future<Map> joinGroup(String id) => _post('/groups/$id/join', {});
  static Future<Map> addGroupMember(String id, String userId) =>
      _post('/groups/$id/members', {'user_id': userId});
  static Future<Map> removeGroupMember(String id, String userId) =>
      _delete('/groups/$id/members/$userId');
  static Future<Map> promoteGroupAdmin(String id, String userId) =>
      _post('/groups/$id/admins/$userId', {});
  static Future<Map> demoteGroupAdmin(String id, String userId) =>
      _delete('/groups/$id/admins/$userId');

  static Future<List<Map>> getGroupMessages(String groupId) async {
    final d = await _getSafe('/groups/$groupId/messages', timeoutSec: 20);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<Map> sendGroupMessage(
    String groupId,
    String content, {
    String? mediaUrl,
    String messageType = 'text',
    Map? replyTo,
  }) =>
      _post('/groups/$groupId/messages', {
        'content': content,
        'message_type': messageType,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyTo != null) 'reply_to': replyTo,
      });

  static Future<void> ackGroupMessages(String groupId, List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _post('/groups/$groupId/messages/ack', {'ids': ids});
    } catch (_) {}
  }

  static Future<Map> deleteGroupMessage(String groupId, String messageId) =>
      _delete('/groups/$groupId/messages/$messageId');

  static Future<Map> editGroupMessage(
          String groupId, String messageId, String content) =>
      _put('/groups/$groupId/messages/$messageId', {'content': content});

  static Future<Map> reactToGroupMessage(
          String groupId, String messageId, String emoji) =>
      _post('/groups/$groupId/messages/$messageId/react', {'emoji': emoji});

  /// Same idea as [syncMessages] but for group chat's reactions + seen-by.
  static Future<Map<String, Map>> syncGroupMessages(
      String groupId, List<String> ids) async {
    if (ids.isEmpty) return {};
    try {
      final d = await _post('/groups/$groupId/messages/sync', {'ids': ids});
      if (d['success'] != true) return {};
      return (d['data'] as Map)
          .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)));
    } catch (_) {
      return {};
    }
  }

  // ─── FOLLOWERS / FOLLOWING LISTS ───────────────────────────────────────────
  static Future<List<Map>> getFollowers(String userId,
      {int limit = 40, int offset = 0}) async {
    final d = await _getSafe(
        '/users/$userId/followers?limit=$limit&offset=$offset',
        timeoutSec: 20);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<List<Map>> getFollowing(String userId,
      {int limit = 40, int offset = 0}) async {
    final d = await _getSafe(
        '/users/$userId/following?limit=$limit&offset=$offset',
        timeoutSec: 20);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ─── CHAT DELETE ────────────────────────────────────────────────────────────
  static Future<Map> deleteChat(String chatId) => _delete('/chats/$chatId');

  // ─── SIGMA NEARBY ──────────────────────────────────────────────────────────
  /// Opens a Nearby session: the returned token is advertised over BLE.
  static Future<String?> nearbyStart() async {
    try {
      final d = await _post('/nearby/start', {});
      if (d['success'] != true) return null;
      return (d['data']?['token'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> nearbyStop() async {
    try {
      await _post('/nearby/stop', {});
    } catch (_) {}
  }

  /// Resolves a discovered token to its owner's public profile.
  static Future<Map?> nearbyPeek(String token) async {
    final d = await _getSafe(
        '/nearby/peek?token=${Uri.encodeQueryComponent(token)}',
        timeoutSec: 10);
    if (d['success'] != true || d['data'] == null) return null;
    return Map.from(d['data']);
  }

  /// Performs the exchange: mutual follow + Aura. Returns the other profile.
  static Future<Map?> nearbyConnect(String token) async {
    try {
      final d = await _post('/nearby/connect', {'token': token});
      if (d['success'] != true || d['data']?['user'] == null) return null;
      return Map.from(d['data']['user']);
    } catch (_) {
      return null;
    }
  }

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
    final d = await _post(
        '/ai/chat', {'messages': messages, 'lang': appConfig.value.lang});
    return (d['reply'] ?? S.tr('aiUnavailable')).toString();
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
  /// Fire-and-forget ping to wake the backend. Render's free tier spins the
  /// server down after inactivity and a cold start takes ~50s — calling this
  /// at app launch means the media catalogs (podcasts / audiobooks) are already
  /// warm by the time the user opens "Ритм".
  static void warmUp() {
    http
        .get(Uri.parse('$kApiUrl/health'))
        .timeout(const Duration(seconds: 60))
        .catchError((_) => http.Response('', 500));
  }

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
    final d = await _getSafe(
        '/podcast/search?term=${Uri.encodeQueryComponent(term)}',
        timeoutSec: 45);
    if (d['success'] != true) return [];
    // Tag the media kind so History / Favourites can be filtered per section
    // (podcast history must not leak music or audiobooks, and vice-versa).
    return ((d['data'] ?? []) as List)
        .map((e) => {...Map.from(e), 'kind': 'podcast'})
        .toList();
  }

  static Future<List<Map>> fetchEpisodes(String feedUrl) async {
    final d = await _getSafe(
        '/podcast/episodes?feed=${Uri.encodeQueryComponent(feedUrl)}');
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List).map((e) => Map.from(e)).toList();
  }

  /// Get-or-create a stable shareable id for one episode. Returns null if the
  /// server can't mint one (migration not run yet, or offline) — callers
  /// should fall back to the raw episode url rather than share a broken link.
  static Future<String?> sharePodcastEpisode(Map episode) async {
    try {
      final d = await _post('/podcast/share', {
        'feedUrl': episode['feedUrl'],
        'audio': episode['audio'],
        'title': episode['title'],
        'artist': episode['showTitle'],
        'artwork': episode['artwork'],
        'duration': episode['duration'],
      });
      return d['success'] == true ? d['id']?.toString() : null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves a `/podcast/<id>` link back to a playable episode.
  static Future<Map?> podcastEpisodeById(String id) async {
    try {
      final d = await _get('/podcast/share/$id');
      if (d['success'] != true) return null;
      final ep = d['episode'];
      return ep == null ? null : Map<String, dynamic>.from(ep);
    } catch (_) {
      return null;
    }
  }

  // ─── AUDIOBOOKS (LibriVox — public domain, via backend proxy) ─────────────
  static Future<List<Map>> searchAudiobooks(String term,
      {String genre = '', String language = ''}) async {
    var q = '/audiobooks/search?term=${Uri.encodeQueryComponent(term)}';
    if (genre.isNotEmpty) q += '&genre=${Uri.encodeQueryComponent(genre)}';
    if (language.isNotEmpty) {
      q += '&language=${Uri.encodeQueryComponent(language)}';
    }
    final d = await _getSafe(q, timeoutSec: 45);
    if (d['success'] != true) return [];
    return ((d['data'] ?? []) as List)
        .map((e) => {...Map.from(e), 'kind': 'book'})
        .toList();
  }

  // ─── MUSIC (Audius — free legal streaming API, commercial use allowed) ────
  static const String _audiusApp = 'app_name=sigmacta';

  // A single hard-coded discovery node is flaky: when it is briefly down or
  // geo-throttled the whole music picker shows "Ничего не найдено". So we try a
  // list of nodes in order (remembering the first that answers) and fall back to
  // the load-balanced gateway. Stream URLs always use the stable gateway so that
  // songs saved to History / Favourites keep working even if a node disappears.
  static const String _audiusGateway = 'https://api.audius.co';
  static const List<String> _audiusHosts = [
    'https://discoveryprovider.audius.co',
    'https://discoveryprovider2.audius.co',
    'https://discoveryprovider3.audius.co',
    _audiusGateway,
  ];
  static String? _audiusHost; // the last node that answered (cached)

  static Map _audiusTrack(Map t) => {
        'id': t['id']?.toString() ?? '',
        'title': t['title'] ?? 'Track',
        'showTitle': (t['user']?['name'] ?? '').toString(),
        'artwork': (t['artwork']?['480x480'] ?? t['artwork']?['150x150'] ?? '')
            .toString(),
        'audio': '$_audiusGateway/v1/tracks/${t['id']}/stream?$_audiusApp',
        'duration': t['duration']?.toString() ?? '',
        'kind': 'music', // distinguishes music from podcasts/books locally
      };

  /// Hits an Audius `/v1` endpoint, trying each node until one returns data.
  /// `path` starts after `/v1`, e.g. `/tracks/trending?...`.
  static Future<List<Map>> _audiusGet(String path) async {
    final hosts = <String>[
      if (_audiusHost != null) _audiusHost!,
      ..._audiusHosts.where((h) => h != _audiusHost),
    ];
    for (final host in hosts) {
      try {
        final r = await http
            .get(Uri.parse('$host/v1$path'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) continue;
        final data = (jsonDecode(r.body)['data'] ?? []) as List;
        _audiusHost = host; // remember the node that worked
        return data.map((t) => _audiusTrack(Map.from(t))).toList();
      } catch (_) {
        // try the next node
      }
    }
    return [];
  }

  static Future<List<Map>> musicTrending({String genre = ''}) {
    final g =
        genre.isNotEmpty ? '&genre=${Uri.encodeQueryComponent(genre)}' : '';
    return _audiusGet('/tracks/trending?$_audiusApp$g');
  }

  static Future<List<Map>> musicSearch(String q) => _audiusGet(
      '/tracks/search?query=${Uri.encodeQueryComponent(q)}&$_audiusApp');

  /// Resolves a single Audius track by id — the shared-link case, where
  /// there's no search query, only the id embedded in a `sigmacta.pages.dev/music/<id>`
  /// link. Unlike [_audiusGet], a miss here (deleted/unknown track) must be
  /// distinguishable from a normal empty list, hence the nullable return.
  static Future<Map?> musicTrackById(String id) async {
    final hosts = <String>[
      if (_audiusHost != null) _audiusHost!,
      ..._audiusHosts.where((h) => h != _audiusHost),
    ];
    for (final host in hosts) {
      try {
        final r = await http
            .get(Uri.parse('$host/v1/tracks/$id?$_audiusApp'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) continue;
        final data = jsonDecode(r.body)['data'];
        if (data == null) return null;
        _audiusHost = host;
        return _audiusTrack(Map.from(data));
      } catch (_) {
        // try the next node
      }
    }
    return null;
  }

  // ─── GIFs (Tenor via backend) ──────────────────────────────────────────────
  static Future<List> searchGifs(String query, {bool stickers = false}) async {
    if (stickers) {
      final d = await _getSafe(
          '/gifs?q=${Uri.encodeQueryComponent(query)}&kind=stickers',
          timeoutSec: 20);
      return d['success'] == true ? (d['data'] ?? []) : [];
    }
    return _searchGifsPlain(query);
  }

  static Future<List> _searchGifsPlain(String query) async {
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
