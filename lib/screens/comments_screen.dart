import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../constants.dart';

class CommentsScreen extends StatefulWidget {
  final Map post;
  final Map user;
  const CommentsScreen({Key? key, required this.post, required this.user})
      : super(key: key);
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _commentCtrl = TextEditingController();
  List comments = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    comments = await ApiService.getComments(widget.post['id']);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    _commentCtrl.clear();
    await ApiService.addComment(widget.post['id'], widget.user['id'], text);
    _load();
  }

  Future<void> _deleteComment(String id) async {
    await ApiService.deleteComment(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comments')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(widget.post['username'] ?? 'User',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: kGold)),
                const SizedBox(height: 4),
                Text(widget.post['content'] ?? ''),
              ]),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : comments.isEmpty
                  ? const Center(
                      child: Text('No comments yet',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: comments.length,
                      itemBuilder: (context, i) {
                        final c = comments[i];
                        final isOwn = c['user_id'] == widget.user['id'];
                        return ListTile(
                          leading: c['user_avatar'] != null
                              ? CircleAvatar(
                                  backgroundImage: CachedNetworkImageProvider(
                                      c['user_avatar']))
                              : const CircleAvatar(
                                  backgroundColor: kGold,
                                  child: Icon(Icons.person,
                                      color: Colors.black)),
                          title: Text(c['username'] ?? 'User',
                              style: const TextStyle(
                                  color: kGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          subtitle: Text(c['content'] ?? ''),
                          trailing: isOwn
                              ? IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red, size: 18),
                                  onPressed: () => _deleteComment(c['id']))
                              : null,
                        );
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: kDark,
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Write a comment...'))),
            const SizedBox(width: 8),
            ElevatedButton(
                onPressed: _addComment,
                style:
                    ElevatedButton.styleFrom(minimumSize: const Size(56, 48)),
                child: const Icon(Icons.send, color: Colors.black)),
          ]),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }
}
