import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../constants.dart';

class PostCard extends StatelessWidget {
  final Map post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onUserTap;

  const PostCard({
    Key? key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onUserTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isLiked = post['is_liked'] == true;
    final username = post['username'] ?? 'User';
    final avatarUrl = post['user_avatar'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(
              onTap: onUserTap,
              child: avatarUrl != null
                  ? CircleAvatar(
                      radius: 18,
                      backgroundImage: CachedNetworkImageProvider(avatarUrl))
                  : const CircleAvatar(
                      radius: 18,
                      backgroundColor: kGold,
                      child: Icon(Icons.person, size: 16, color: Colors.black)),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onUserTap,
              child: Text(username,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: kGold)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(post['content'] ?? '', style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 10),
          Row(children: [
            GestureDetector(
              onTap: onLike,
              child: Row(children: [
                Icon(isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.grey, size: 20),
                const SizedBox(width: 4),
                Text('${post['likes_count'] ?? 0}',
                    style: TextStyle(
                        color: isLiked ? Colors.red : Colors.grey,
                        fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: onComment,
              child: Row(children: [
                const Icon(Icons.comment_outlined,
                    color: Colors.grey, size: 20),
                const SizedBox(width: 4),
                Text('${post['comments_count'] ?? 0}',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }
}
