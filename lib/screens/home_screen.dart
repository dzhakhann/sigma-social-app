import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'comments_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'story_view_screen.dart';
import 'story_editor_screen.dart';
import 'story_camera_screen.dart';
import 'podcast_player_screen.dart';
import '../services/podcast_store.dart';
import '../services/podcast_audio.dart';
import 'notifications_screen.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'goals_screen.dart';
import 'year_review_screen.dart';
import '../services/session.dart';
import '../widgets/link_preview.dart';
import '../widgets/shimmer.dart';
import '../services/events.dart';

// ════════════════════════════════════════════════════════════════════════════
//  HOME — Threads-style feed with stories row + FAB for compose.
// ════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  final Map user;
  const HomeScreen({super.key, required this.user});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List _stories = [];
  List _goals = [];
  Map _wrapped = {};
  String _ai = '';
  Map _horo = {};
  bool _loading = false;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
    feedRefresh.addListener(_onFeedRefresh);
  }

  void _onFeedRefresh() => _load();

  // Home is now a personal dashboard: goals, AI advice, statistics.
  Future<void> _load() async {
    if (mounted && _goals.isEmpty) setState(() => _loading = true);
    final uid = widget.user['id'].toString();
    final goals = await ApiService.getGoals(uid);
    final wrapped = await ApiService.getWrapped(uid);
    if (mounted) {
      setState(() {
        _goals = goals;
        _wrapped = wrapped;
        _loading = false;
      });
    }
    _loadStories();
    _loadAi();
    _loadHoro();
    _updateStreak();
    _loadLastListened();
  }

  // Horoscope is cached per week (updates only on Monday) so it's instant and
  // doesn't hit the AI every time. The cache is per-language, so switching
  // EN/RU regenerates it in the new language.
  String _mondayKey() {
    final now = DateTime.now();
    final m = now.subtract(Duration(days: now.weekday - 1));
    return '${m.year}-${m.month}-${m.day}';
  }

  // The AI daily tip refreshes once a day at 06:00 local time: everything
  // before 6 AM still belongs to the previous day.
  String _sixAmKey() {
    final d = DateTime.now().subtract(const Duration(hours: 6));
    return '${d.year}-${d.month}-${d.day}';
  }

  String get _lang => appConfig.value.lang;

  Future<void> _loadHoro({bool force = false}) async {
    final monday = _mondayKey();
    final p = await SharedPreferences.getInstance();
    if (!force) {
      final cached = p.getString('horo_cache');
      if (cached != null) {
        try {
          final m = jsonDecode(cached) as Map;
          if (m['week'] == monday && m['lang'] == _lang) {
            if (mounted) setState(() => _horo = Map.from(m));
            return; // fresh for this week + language
          }
        } catch (_) {}
      }
    }
    try {
      final h = await ApiService.horoscope();
      if ((h['sign'] ?? '').toString().isNotEmpty &&
          (h['text'] ?? '').toString().isNotEmpty) {
        final store = {
          'week': monday,
          'lang': _lang,
          'sign': h['sign'],
          'emoji': h['emoji'],
          'text': h['text'],
        };
        await p.setString('horo_cache', jsonEncode(store));
        if (mounted) setState(() => _horo = store);
      } else if (mounted) {
        setState(() => _horo = Map.from(h));
      }
    } catch (_) {}
  }

  Future<void> _loadAi({bool force = false}) async {
    final day = _sixAmKey();
    final p = await SharedPreferences.getInstance();
    if (!force) {
      final cached = p.getString('ai_tip_cache');
      if (cached != null) {
        try {
          final m = jsonDecode(cached) as Map;
          if (m['day'] == day && m['lang'] == _lang) {
            // Same day (6 AM boundary) + same language → reuse.
            if (mounted) {
              setState(() {
                _ai = (m['text'] ?? '').toString();
                _aiLoading = false;
              });
            }
            return;
          }
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _aiLoading = true);
    String text = '';
    try {
      text = await ApiService.aiRecommend();
    } catch (_) {}
    final clean = _cleanMarkdown(text);
    if (clean.isNotEmpty) {
      await p.setString('ai_tip_cache',
          jsonEncode({'day': day, 'lang': _lang, 'text': clean}));
    }
    if (mounted) {
      setState(() {
        _ai = clean;
        _aiLoading = false;
      });
    }
  }

  // Regenerate AI tip + horoscope when the user switches EN/RU.
  String? _lastLang;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = AppScope.of(context).lang;
    if (_lastLang != null && _lastLang != lang) {
      _loadAi();
      _loadHoro();
    }
    _lastLang = lang;
  }

  // The AI sometimes replies in Markdown; show clean, plain text.
  static String _cleanMarkdown(String s) {
    var t = s;
    t = t.replaceAll(RegExp(r'\*\*|__'), ''); // bold
    t = t.replaceAll(RegExp(r'(?<!\w)[*_](?!\s)'), ''); // stray emphasis
    t = t.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), ''); // headings
    t = t.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• '); // bullets
    t = t.replaceAll('`', '');
    return t.trim();
  }

  Future<void> _loadStories() async {
    final data = await ApiService.getStories();
    if (mounted) setState(() => _stories = data);
  }

  Map<String, List> get _grouped {
    final Map<String, List> g = {};
    for (var s in _stories) {
      final uid = s['user_id']?.toString();
      if (uid == null || uid == widget.user['id'].toString()) continue;
      g.putIfAbsent(uid, () => []).add(s);
    }
    return g;
  }

  void _openStory(List uStories) {
    final all = _grouped.values.toList();
    int gi = 0;
    for (int i = 0; i < all.length; i++) {
      if (all[i].isNotEmpty &&
          all[i][0]['user_id'] == uStories[0]['user_id']) {
        gi = i;
        break;
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewScreen(
          stories: uStories,
          allGroups: all,
          groupIndex: gi,
          startIndex: 0,
          user: widget.user,
          onStoryDeleted: _loadStories,
        ),
      ),
    );
  }

  Future<void> _addStory({ImageSource? source}) async {
    Uint8List? bytes;
    if (kIsWeb || source == ImageSource.gallery) {
      // Web (no in-app camera) or explicit gallery request.
      final picker = ImagePicker();
      final img = await picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1080, imageQuality: 85);
      if (img == null) return;
      bytes = await img.readAsBytes();
    } else {
      // Telegram-style: tap "Me" → straight into the in-app camera
      // (shutter, flash, flip, gallery shortcut inside).
      bytes = await Navigator.push<Uint8List>(
        context,
        PageRouteBuilder(
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 260),
          pageBuilder: (_, __, ___) => const StoryCameraScreen(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
        ),
      );
      if (bytes == null) return;
    }
    if (!mounted) return;
    // Instagram-style editor: preview + text overlay before publishing.
    final edited = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => StoryEditorScreen(imageBytes: bytes!)),
    );
    if (edited == null) return;
    final data =
        await ApiService.uploadStory(widget.user['id'], base64Encode(edited));
    if (data['success'] == true) _loadStories();
  }


  // ─── Dashboard cards ──────────────────────────────────────────────────────
  Widget _greeting(BrutalColors c) {
    final name = (widget.user['first_name'] ?? widget.user['username'] ?? '')
        .toString();
    final hour = DateTime.now().hour;
    final part = hour < 6
        ? context.t('night')
        : hour < 12
            ? context.t('morning')
            : hour < 18
                ? context.t('afternoon')
                : context.t('evening');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Text(
        name.isEmpty ? part : '$part, $name',
        style: TextStyle(
            color: c.ink, fontSize: 22, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _aiCard(BrutalColors c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          c.accent.withOpacity(0.20),
          c.accent3.withOpacity(0.10),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome_rounded, color: c.accent, size: 20),
            const SizedBox(width: 8),
            Text(context.t('aiTip'),
                style: TextStyle(
                    color: c.ink, fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            GestureDetector(
              onTap: _aiLoading ? null : () => _loadAi(force: true),
              child: Icon(Icons.refresh_rounded, color: c.inkSoft, size: 20),
            ),
          ]),
          const SizedBox(height: 10),
          if (_aiLoading)
            Row(children: [
              SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.accent)),
              const SizedBox(width: 10),
              Text(context.t('aiThinking'),
                  style: TextStyle(color: c.inkSoft, fontSize: 13)),
            ])
          else
            Text(
              _ai.isEmpty ? context.t('aiEmpty') : _ai,
              style: TextStyle(color: c.ink, height: 1.45, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _goalsHeader(BrutalColors c) {
    final active = _goals.where((g) => g['status'] != 'done').length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(children: [
        Text(context.t('myGoals'),
            style: TextStyle(
                color: c.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        if (active > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: c.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Text('$active ${context.t('active')}',
                style: TextStyle(
                    color: c.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => GoalsScreen(user: widget.user)),
          ).then((_) => _load()),
          child: Text(context.t('seeAll'),
              style: TextStyle(
                  color: c.accent, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _noGoals(BrutalColors c) => Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: c.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(Icons.flag_outlined, color: c.inkSoft, size: 34),
          const SizedBox(height: 10),
          Text(context.t('noGoals'),
              style: TextStyle(color: c.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(context.t('noGoalsHint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 13)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => GoalsScreen(user: widget.user)),
            ).then((_) => _load()),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                  gradient: c.buttonGradient,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(context.t('setGoal'),
                  style: TextStyle(
                      color: c.onAccent, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );

  Widget _goalTile(BrutalColors c, Map g) {
    final done = g['status'] == 'done';
    final progress = ((g['progress'] ?? (done ? 100 : 0)) as num).toDouble();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: done ? c.accent.withOpacity(0.35) : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.flag_rounded,
                size: 18, color: done ? c.accent : c.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text((g['title'] ?? '').toString(),
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration:
                          done ? TextDecoration.lineThrough : null)),
            ),
            Text('${progress.toInt()}%',
                style: TextStyle(
                    color: c.inkSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: c.ink.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          backgroundColor: c.surface,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(c)),
              SliverToBoxAdapter(child: _storiesRow(c)),
              SliverToBoxAdapter(child: _greeting(c)),
              SliverToBoxAdapter(child: _aiCard(c)),
              SliverToBoxAdapter(child: _StatsFooter(user: widget.user)),
              SliverToBoxAdapter(child: _goalsHeader(c)),
              if (_loading)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator())))
              else if (_goals.isEmpty)
                SliverToBoxAdapter(child: _noGoals(c))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _goalTile(c, _goals[i]),
                    childCount: _goals.length,
                  ),
                ),
              SliverToBoxAdapter(child: _horoCard(c)),
              SliverToBoxAdapter(child: _streakCard(c)),
              SliverToBoxAdapter(child: _continueListeningCard(c)),
              SliverToBoxAdapter(child: _quoteCard(c)),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 🔥 Day streak (stored locally: just two small values) ────────────────
  int _streak = 0;

  Future<void> _updateStreak() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    final last = p.getString('streak_last') ?? '';
    var count = p.getInt('streak_count') ?? 0;
    if (last != today) {
      final y = now.subtract(const Duration(days: 1));
      final yesterday = '${y.year}-${y.month}-${y.day}';
      count = last == yesterday ? count + 1 : 1;
      await p.setString('streak_last', today);
      await p.setInt('streak_count', count);
    }
    if (mounted) setState(() => _streak = count);
  }

  Widget _streakCard(BrutalColors c) {
    if (_streak <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.ink.withOpacity(0.06)),
      ),
      child: Row(children: [
        const Text('🔥', style: TextStyle(fontSize: 30)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t('streakDays').replaceAll('{n}', '$_streak'),
                style: TextStyle(
                    color: c.ink, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(context.t('streakHint'),
                style: TextStyle(color: c.inkSoft, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  // ─── 🎵 Continue listening (last item from local history) ─────────────────
  Map? _lastListened;

  Future<void> _loadLastListened() async {
    final h = await PodcastStore.history();
    if (mounted && h.isNotEmpty) setState(() => _lastListened = h.first);
  }

  Widget _continueListeningCard(BrutalColors c) {
    final ep = _lastListened;
    if (ep == null) return const SizedBox.shrink();
    final art = (ep['artwork'] ?? '').toString();
    return GestureDetector(
      onTap: () {
        PodcastAudio.instance.playList([Map.from(ep)], 0);
        Navigator.push(context, PodcastPlayerScreen.route());
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.ink.withOpacity(0.06)),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: art.isEmpty
                ? Container(
                    width: 52, height: 52,
                    color: c.surface2,
                    child: Icon(Icons.music_note_rounded, color: c.inkSoft))
                : CachedNetworkImage(
                    imageUrl: art, width: 52, height: 52, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('continueListening'),
                  style: TextStyle(
                      color: c.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text((ep['title'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Text((ep['showTitle'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.inkSoft, fontSize: 12)),
            ]),
          ),
          Icon(Icons.play_circle_fill_rounded, color: c.accent, size: 36),
        ]),
      ),
    );
  }

  // ─── 💬 Quote of the day (local catalog — free, no API) ───────────────────
  static const _quotesEn = [
    'The secret of getting ahead is getting started.',
    'Small steps every day lead to big results.',
    'Discipline is choosing what you want most over what you want now.',
    'You do not have to be great to start, but you have to start to be great.',
    'Success is the sum of small efforts repeated daily.',
    'The best time to plant a tree was 20 years ago. The second best is now.',
    'Dream big. Start small. Act now.',
    'Motivation gets you going, habit keeps you growing.',
    'Focus on progress, not perfection.',
    'Every day is a chance to get better.',
    'Do something today that your future self will thank you for.',
    'Great things never come from comfort zones.',
    'Energy flows where attention goes.',
    'One goal at a time. One day at a time.',
  ];
  static const _quotesRu = [
    'Секрет успеха — просто начать.',
    'Маленькие шаги каждый день ведут к большим результатам.',
    'Дисциплина — выбирать то, чего хочешь больше всего, а не то, чего хочется сейчас.',
    'Не обязательно быть великим, чтобы начать. Но нужно начать, чтобы стать великим.',
    'Успех — это сумма маленьких усилий, повторяемых ежедневно.',
    'Лучшее время посадить дерево было 20 лет назад. Второе лучшее — сегодня.',
    'Мечтай масштабно. Начинай с малого. Действуй сейчас.',
    'Мотивация запускает, привычка ведёт вперёд.',
    'Фокус на прогрессе, а не на идеале.',
    'Каждый день — шанс стать лучше.',
    'Сделай сегодня то, за что будущий ты скажет спасибо.',
    'Великое не рождается в зоне комфорта.',
    'Энергия там, где твоё внимание.',
    'Одна цель за раз. Один день за раз.',
  ];

  Widget _quoteCard(BrutalColors c) {
    final lang = AppScope.of(context).lang;
    final list = lang == 'ru' ? _quotesRu : _quotesEn;
    final day = DateTime.now().difference(DateTime(2026)).inDays;
    final quote = list[day % list.length];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          c.accent3.withOpacity(0.14),
          c.accent.withOpacity(0.08),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('💬', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(context.t('quoteOfDay'),
              style: TextStyle(
                  color: c.inkSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text(quote,
            style: TextStyle(
                color: c.ink,
                fontSize: 14.5,
                height: 1.45,
                fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _horoCard(BrutalColors c) {
    final sign = (_horo['sign'] ?? '').toString();
    final emoji = (_horo['emoji'] ?? '✨').toString();
    final text = (_horo['text'] ?? '').toString();
    if (sign.isEmpty) {
      // No birthday yet → gentle prompt.
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: c.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Text('🔮', style: TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                context.t('horoFill'),
                style: TextStyle(color: c.inkSoft, fontSize: 13, height: 1.4)),
          ),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.accent3.withOpacity(0.22),
            c.accent.withOpacity(0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Round zodiac emblem
            Container(
              width: 52, height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  c.accent.withOpacity(0.9),
                  c.accent3.withOpacity(0.9),
                ]),
                boxShadow: [
                  BoxShadow(
                      color: c.accent.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sign,
                      style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17)),
                  Text(context.t('horoWeek'),
                      style: TextStyle(color: c.inkSoft, fontSize: 12)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _loadHoro(force: true),
              child: Icon(Icons.refresh_rounded, color: c.inkSoft, size: 20),
            ),
          ]),
          const SizedBox(height: 12),
          Text(text.isEmpty ? context.t('loadingForecast') : text,
              style: TextStyle(color: c.ink, height: 1.5, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _header(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          // Logo
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: c.buttonGradient,
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: const Text('Σ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SearchScreen(user: widget.user)),
            ),
            child: Icon(Icons.search_rounded, color: c.ink, size: 25),
          ),
          const SizedBox(width: 18),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => NotificationsScreen(user: widget.user)),
            ),
            child: Icon(Icons.notifications_none_rounded, color: c.ink, size: 25),
          ),
          const SizedBox(width: 18),
          GestureDetector(
            onTap: _openFeeds,
            child: Icon(Icons.menu, color: c.ink, size: 24),
          ),
        ],
      ),
    );
  }


  // "Ленты" side panel opened by the hamburger — mirrors the Figma prototype.
  void _openFeeds() {
    final c = context.k;
    Widget item(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return ListTile(
        leading: Icon(icon, color: color ?? c.ink, size: 22),
        title: Text(label,
            style: TextStyle(
                color: color ?? c.ink,
                fontSize: 15.5,
                fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
    }

    void soon() {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('comingSoon'))));
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: c.ink.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.t('menu'),
                    style: TextStyle(
                        color: c.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            item(Icons.flag_outlined, context.t('myGoals'), () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => GoalsScreen(user: widget.user)),
              ).then((_) => _load());
            }),
            item(Icons.insights_rounded, context.t('mYearReport'), () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => YearReviewScreen(
                        user: widget.user, year: DateTime.now().year)),
              );
            }),
            Divider(height: 12, color: c.ink.withOpacity(0.07)),
            item(Icons.settings_outlined, context.t('settings'), () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsScreen(user: widget.user)),
              );
            }),
            item(Icons.help_outline_rounded, context.t('mHelp'), () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: c.surface,
                  title: Text(context.t('helpTitle'), style: TextStyle(color: c.ink)),
                  content: Text(context.t('helpBody'),
                      style: TextStyle(color: c.inkSoft, height: 1.4)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.t('ok'))),
                  ],
                ),
              );
            }),
            item(Icons.logout_rounded, context.t('logout'), () {
              Navigator.pop(context);
              _logout();
            }, color: c.danger),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await Session.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  Widget _storiesRow(BrutalColors c) {
    final myStories = _stories
        .where(
            (s) => s['user_id'].toString() == widget.user['id'].toString())
        .toList();
    final grouped = _grouped;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            // Telegram/Instagram logic: no story → tap opens the camera;
            // has story → tap VIEWS it, the "+" badge adds a new one.
            _MyStoryBtn(
              user: widget.user,
              hasStory: myStories.isNotEmpty,
              onAdd: _addStory,
              onTap: () {
                if (myStories.isEmpty) {
                  _addStory();
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryViewScreen(
                        stories: myStories,
                        allGroups: [myStories],
                        groupIndex: 0,
                        startIndex: 0,
                        user: widget.user,
                        onStoryDeleted: _loadStories,
                      ),
                    ),
                  );
                }
              },
            ),
            ...grouped.values.map((uStories) => _StoryAvatar(
                  stories: uStories,
                  onTap: () => _openStory(uStories),
                )),
          ],
        ),
      ),
    );
  }

  Widget _empty(BrutalColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
      child: Column(
        children: [
          Icon(Icons.dynamic_feed_rounded, size: 56, color: c.inkSoft),
          const SizedBox(height: 14),
          Text(context.t('nothingYet'),
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 18, color: c.ink)),
          const SizedBox(height: 6),
          Text(context.t('beFirst'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkSoft, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    feedRefresh.removeListener(_onFeedRefresh);
    super.dispose();
  }
}

// ─── THREADS-STYLE POST ───────────────────────────────────────────────────────
class _ThreadsPost extends StatelessWidget {
  final Map post;
  final Map user;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onShare;
  final VoidCallback onProfileTap;
  final VoidCallback onMore;

  const _ThreadsPost({
    required this.post,
    required this.user,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onShare,
    required this.onProfileTap,
    required this.onMore,
  });

  String _time() {
    final raw = post['created_at'];
    if (raw == null) return '';
    try {
      return timeago.format(DateTime.parse(raw.toString()).toLocal(),
          locale: 'en_short');
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final username = (post['username'] ?? 'user').toString();
    final avatar = post['user_avatar'] ?? post['avatar_url'];
    final content = (post['content'] ?? '').toString();
    final image = post['image_url'];
    final liked = post['is_liked'] == true;
    final likes = (post['likes_count'] ?? 0);
    final comments = (post['comments_count'] ?? 0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: c.ink.withOpacity(0.06), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + thread line ──────────────────────────────────
          Column(
            children: [
              GestureDetector(
                onTap: onProfileTap,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: c.surface2,
                  backgroundImage: avatar != null
                      ? CachedNetworkImageProvider(avatar.toString())
                      : null,
                  child: avatar == null
                      ? Text(
                          (username.isNotEmpty ? username[0] : '?')
                              .toUpperCase(),
                          style: TextStyle(
                              color: c.ink, fontWeight: FontWeight.w700))
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 2,
                height: 30,
                decoration: BoxDecoration(
                  color: c.ink.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // ── Post content ─────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username row — time + ⋯ pinned to the top-right corner.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: onProfileTap,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            username,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: c.ink),
                          ),
                        ),
                      ),
                    ),
                    if (post['is_verified'] == true) ...[
                      const SizedBox(width: 4),
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.verified_rounded, size: 14),
                      ),
                    ],
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(_time(),
                          style: TextStyle(fontSize: 12, color: c.inkSoft)),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onMore,
                      child: Icon(Icons.more_horiz, size: 20, color: c.inkSoft),
                    ),
                  ],
                ),

                // Content text
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: TextStyle(
                        fontSize: 15, height: 1.35, color: c.ink),
                  ),
                ],

                // Link preview (Telegram-style unfurl)
                if (image == null && firstUrl(content) != null)
                  LinkPreviewCard(url: firstUrl(content)!),

                // Image
                if (image != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: image.toString(),
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          height: 200, color: c.surface2),
                    ),
                  ),
                ],

                // ── Action buttons (Threads-style) ────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _ActionIcon(
                        icon: liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        label: likes > 0 ? '$likes' : '',
                        color: liked ? c.danger : c.inkSoft,
                        onTap: onLike,
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        icon: Icons.mode_comment_outlined,
                        label: comments > 0 ? '$comments' : '',
                        color: c.inkSoft,
                        onTap: onComment,
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        icon: Icons.repeat_rounded,
                        label: '',
                        color: c.inkSoft,
                        onTap: onRepost,
                      ),
                      const SizedBox(width: 16),
                      _ActionIcon(
                        icon: Icons.send_outlined,
                        label: '',
                        color: c.inkSoft,
                        onTap: onShare,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Threads-style action icon with optional count label ─────────────────────
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionIcon(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── STORY WIDGETS ────────────────────────────────────────────────────────────
class _MyStoryBtn extends StatelessWidget {
  final Map user;
  final bool hasStory;
  final VoidCallback onTap;
  final VoidCallback? onAdd; // "+" badge — always opens the camera
  const _MyStoryBtn({
    required this.user,
    required this.hasStory,
    required this.onTap,
    this.onAdd,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 66,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(children: [
            _StoryRing(url: user['avatar_url'], hasStory: hasStory, size: 56),
            Positioned(
              bottom: 0,
              right: 4,
              child: GestureDetector(
                onTap: onAdd ?? onTap,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.bg, width: 2)),
                  child: const Icon(Icons.add, size: 12, color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 5),
          Text(context.t('me'),
              style: TextStyle(fontSize: 11, color: c.inkSoft),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final List stories;
  final VoidCallback onTap;
  const _StoryAvatar({required this.stories, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final first = stories.first;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: SizedBox(
          width: 66,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            _StoryRing(url: first['user_avatar'], hasStory: true, size: 56),
            const SizedBox(height: 5),
            Text(first['username'] ?? 'User',
                style: TextStyle(fontSize: 11, color: c.inkSoft),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

class _StoryRing extends StatelessWidget {
  final String? url;
  final bool hasStory;
  final double size;
  const _StoryRing(
      {required this.url, required this.hasStory, required this.size});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasStory ? c.storyGradient : null,
        color: hasStory ? null : c.surface2,
      ),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.bg),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: url != null
              ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
              : Container(
                  color: c.surface2,
                  child: Icon(Icons.person_rounded, color: c.inkSoft)),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _SheetTile(
      {required this.icon, required this.label, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = context.k;
    final tint = color ?? c.accent;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: color?.withOpacity(0.12) ?? c.surface2,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Text(label,
          style: TextStyle(
              color: color ?? c.ink, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

// ─── HOME STATS FOOTER (animated donut of goal progress) ──────────────────────
class _StatsFooter extends StatefulWidget {
  final Map user;
  const _StatsFooter({required this.user});
  @override
  State<_StatsFooter> createState() => _StatsFooterState();
}

class _StatsFooterState extends State<_StatsFooter> {
  Map _w = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await ApiService.getWrapped(widget.user['id'].toString());
    if (mounted) setState(() { _w = w; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    if (_loading) return const SizedBox.shrink();
    final total = (_w['total'] ?? 0) as int;
    if (total == 0) return const SizedBox.shrink();
    final done = (_w['completed'] ?? 0) as int;
    final rate = (_w['completionRate'] ?? 0) as int;
    final avg = (_w['avgProgress'] ?? 0) as int;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.ink.withOpacity(0.06)),
      ),
      child: Row(children: [
        SizedBox(
          width: 84, height: 84,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: rate / 100),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              painter: _DonutPainter(v, c.accent, c.surface2),
              child: Center(
                child: Text('${(v * 100).round()}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.ink)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('yearProgress'),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: c.ink)),
              const SizedBox(height: 10),
              _statRow(c, context.t('goalsDoneLbl'), '$done / $total'),
              _statRow(c, context.t('avgProgress'), '$avg%'),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _statRow(BrutalColors c, String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l, style: TextStyle(color: c.inkSoft, fontSize: 13)),
              Text(v,
                  style: TextStyle(
                      color: c.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ]),
      );
}

class _DonutPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color bg;
  _DonutPainter(this.value, this.color, this.bg);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final bgPaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, bgPaint);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value.clamp(0, 1), false,
        fgPaint);
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.value != value;
}
