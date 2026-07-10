import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import '../l10n/app_strings.dart';
import 'goals_screen.dart' show catOf;

/// Spotify-Wrapped–style year report, built from the user's goals.
/// Can be captured and published to the in-app story.
class YearReviewScreen extends StatefulWidget {
  final Map user;
  final int year;
  const YearReviewScreen({Key? key, required this.user, required this.year})
      : super(key: key);
  @override
  State<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends State<YearReviewScreen> {
  final GlobalKey _posterKey = GlobalKey();
  Map _w = {};
  bool _loading = true;
  bool _sharing = false;

  String get _uid => widget.user['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await ApiService.getWrapped(_uid, year: widget.year);
    if (mounted) setState(() { _w = w; _loading = false; });
  }

  Future<void> _shareToStory() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _posterKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final b64 = base64Encode(bytes!.buffer.asUint8List());
      final r = await ApiService.uploadStory(_uid, b64);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['success'] == true
              ? context.t('publishedToStory')
              : context.t('publishFailed'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t('couldNotRender'))));
      }
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('myYearOf').replaceAll('{year}', '${widget.year}'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                RepaintBoundary(key: _posterKey, child: _poster(c)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    onPressed: _sharing ? null : _shareToStory,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_sharing ? context.t('publishing') : context.t('publishToStory'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.t('yearTip'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.inkSoft, fontSize: 12, height: 1.4),
                ),
              ],
            ),
    );
  }

  Widget _poster(BrutalColors c) {
    final total = (_w['total'] ?? 0) as int;
    final completed = (_w['completed'] ?? 0) as int;
    final rate = (_w['completionRate'] ?? 0) as int;
    final avg = (_w['avgProgress'] ?? 0) as int;
    final topCat = _w['topCategory'];
    final highlights = (_w['highlights'] ?? []) as List;
    final username = widget.user['username'] ?? 'me';

    if (total == 0) {
      return AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [c.accent, c.accent3]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.t('yearEmpty').replaceAll('{year}', '${widget.year}'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [c.accent, c.accent3]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 34, height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(9)),
                child: const Text('Σ',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18)),
              ),
              const SizedBox(width: 10),
              const Text('SIGMACTA',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 13)),
              const Spacer(),
              Text('${widget.year}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20)),
            ]),
            const Spacer(),
            Text('$completed',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 96,
                    height: 1,
                    fontWeight: FontWeight.w900)),
            Text(
                completed == 1 ? context.t('goalReached') : context.t('goalsReached'),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(context.t('goalsSet').replaceAll('{total}', '$total').replaceAll('{rate}', '$rate'),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 14)),
            const SizedBox(height: 22),
            _stat(context.t('avgProgress'), '$avg%'),
            if (topCat != null)
              _stat(context.t('mainDirection'), context.t('cat_$topCat')),
            const Spacer(),
            if (highlights.isNotEmpty) ...[
              Text(context.t('whatYouAchieved'),
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 11)),
              const SizedBox(height: 8),
              ...highlights.take(4).map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(children: [
                      const Icon(Icons.check_circle,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(h['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ]),
                  )),
              const SizedBox(height: 14),
            ],
            Text('@$username · sigmacta',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 15)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ],
        ),
      );
}
