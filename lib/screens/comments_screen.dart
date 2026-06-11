import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

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
    final c = context.k;
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
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: c.accent)),
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
                  ? Center(
                      child: Text('No comments yet',
                          style: TextStyle(color: c.inkSoft)))
                  : ListView.builder(
                      itemCount: comments.length,
                      itemBuilder: (context, i) {
                        final cm = comments[i];
                        final isOwn = cm['user_id'] == widget.user['id'];
                        return ListTile(
                          leading: cm['user_avatar'] != null
                              ? CircleAvatar(
                                  backgroundImage: CachedNetworkImageProvider(
                                      cm['user_avatar']))
                              : CircleAvatar(
                                  backgroundColor: c.accent,
                                  child: Icon(Icons.person,
                                      color: c.ink)),
                          title: Text(cm['username'] ?? 'User',
                              style: TextStyle(
                                  color: c.accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          subtitle: Text(cm['content'] ?? ''),
                          trailing: isOwn
                              ? IconButton(
                                  icon: Icon(Icons.delete,
                                      color: c.danger, size: 18),
                                  onPressed: () => _deleteComment(cm['id']))
                              : null,
                        );
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: c.bg,
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
                child: Icon(Icons.send, color: c.ink)),
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
