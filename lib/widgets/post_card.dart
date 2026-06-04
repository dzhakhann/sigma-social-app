import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants.dart';

class PostCard extends StatelessWidget {
  final Map post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onUserTap;

  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = post['is_liked'] == true;
    final username = post['username'] ?? 'User';
    final avatarUrl = post['user_avatar'] as String?;
    final imageUrl = post['image_url'] as String?;
    final content = post['content'] as String? ?? '';
    final likesCount = post['likes_count'] ?? 0;
    final commentsCount = post['comments_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      color: kBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            GestureDetector(
              onTap: onUserTap,
              child: _Avatar(url: avatarUrl, size: 40),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: onUserTap,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(username,
                      style: const TextStyle(
                          color: kText,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 1),
                  Text(_timeAgo(post['created_at']),
                      style: const TextStyle(color: kDim, fontSize: 12)),
                ]),
              ),
            ),
            Icon(Icons.more_horiz_rounded, color: kDim, size: 20),
          ]),
        ),

        // Content text
        if (content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(content,
                style: const TextStyle(
                    color: kText, fontSize: 15, height: 1.45)),
          ),

        // Image
        if (imageUrl != null && imageUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 200,
                  color: kSurface,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: kAccent, strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 120,
                  color: kSurface,
                  child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: kDim, size: 40)),
                ),
              ),
            ),
          ),

        // Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 16, 14),
          child: Row(children: [
            _ActionBtn(
              icon: isLiked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isLiked ? kPink : kDim,
              count: likesCount,
              onTap: onLike,
            ),
            const SizedBox(width: 4),
            _ActionBtn(
              icon: Icons.chat_bubble_outline_rounded,
              color: kDim,
              count: commentsCount,
              onTap: onComment,
            ),
            const Spacer(),
            Icon(Icons.bookmark_border_rounded, color: kDim, size: 20),
          ]),
        ),

        const Divider(height: 1),
      ]),
    );
  }

  String _timeAgo(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.color,
      required this.count,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text('$count',
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final double size;
  const _Avatar({this.url, required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: url == null ? kStoryGradient : null,
        image: url != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(url!), fit: BoxFit.cover)
            : null,
      ),
      child: url == null
          ? Center(
              child: Icon(Icons.person_rounded,
                  color: Colors.white, size: size * 0.55))
          : null,
    );
  }
}
