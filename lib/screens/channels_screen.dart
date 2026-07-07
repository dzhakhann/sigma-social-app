import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';
import 'profile_screen.dart';

/// Threads-style channel directory. Each "channel" is a content bot that
/// auto-posts news/sport/movies/etc. Subscribe = follow, so the channel's
/// posts then show up in your Following feed.
class ChannelsScreen extends StatefulWidget {
  final Map user;
  const ChannelsScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List _channels = [];
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.getChannels(widget.user['id'].toString());
    if (mounted) setState(() { _channels = data; _loading = false; });
  }

  Future<void> _toggle(Map ch) async {
    final id = ch['id'].toString();
    if (_busy.contains(id)) return;
    final wasFollowing = ch['is_following'] == true;
    setState(() {
      _busy.add(id);
      ch['is_following'] = !wasFollowing; // optimistic
      ch['followers_count'] =
          (ch['followers_count'] ?? 0) + (wasFollowing ? -1 : 1);
    });
    final uid = widget.user['id'].toString();
    if (wasFollowing) {
      await ApiService.unfollow(uid, id);
    } else {
      await ApiService.follow(uid, id);
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      appBar: AppBar(title: const Text('Channels')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: _channels.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 14),
                      child: Text(
                        'Subscribe to channels for a feed full of news, '
                        'sport, movies, science and more — updated daily.',
                        style: TextStyle(color: c.inkSoft, height: 1.35),
                      ),
                    );
                  }
                  final ch = _channels[i - 1];
                  final following = ch['is_following'] == true;
                  final bio = (ch['bio'] ?? '').toString();
                  final handle = (ch['username'] ?? '').toString();
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.ink.withOpacity(0.06)),
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            user: widget.user,
                            targetUserId: ch['id'],
                            isOwnProfile: false,
                          ),
                        ),
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: c.accent.withOpacity(0.18),
                        backgroundImage: ch['avatar_url'] != null
                            ? CachedNetworkImageProvider(ch['avatar_url'])
                            : null,
                        child: ch['avatar_url'] == null
                            ? Text(
                                bio.isNotEmpty ? bio.characters.first : '#',
                                style: const TextStyle(fontSize: 22),
                              )
                            : null,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              bio.isEmpty ? '@$handle' : bio,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                          if (ch['is_verified'] == true) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded,
                                size: 15, color: c.ink),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        '@$handle · ${ch['followers_count'] ?? 0} subscribers',
                        style: TextStyle(color: c.inkSoft, fontSize: 12),
                      ),
                      trailing: SizedBox(
                        height: 34,
                        child: following
                            ? OutlinedButton(
                                onPressed: () => _toggle(ch),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.inkSoft,
                                  side: BorderSide(color: c.ink.withOpacity(0.2)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 14),
                                ),
                                child: const Text('Subscribed'),
                              )
                            : FilledButton(
                                onPressed: () => _toggle(ch),
                                style: FilledButton.styleFrom(
                                  backgroundColor: c.accent,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 18),
                                ),
                                child: const Text('Subscribe'),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
