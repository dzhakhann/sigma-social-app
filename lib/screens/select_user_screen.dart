import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../constants.dart';
import 'chat_detail_screen.dart';

class SelectUserScreen extends StatefulWidget {
  final Map user;
  const SelectUserScreen({Key? key, required this.user}) : super(key: key);
  @override
  State<SelectUserScreen> createState() => _SelectUserScreenState();
}

class _SelectUserScreenState extends State<SelectUserScreen> {
  List users = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    final all = await ApiService.getUsers();
    if (mounted) {
      setState(() {
        users = all.where((u) => u['id'] != widget.user['id']).toList();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select User')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : users.isEmpty
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (_, i) {
                    final u = users[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      child: ListTile(
                        leading: u['avatar_url'] != null
                            ? CircleAvatar(
                                backgroundImage: CachedNetworkImageProvider(
                                    u['avatar_url']))
                            : const CircleAvatar(
                                backgroundColor: kGold,
                                child: Icon(Icons.person, color: Colors.black)),
                        title: Text(u['username'] ?? 'User'),
                        subtitle: Text(u['email'] ?? '',
                            style: const TextStyle(color: Colors.grey)),
                        onTap: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(
                                      chat: {'name': u['username']},
                                      user: widget.user,
                                      targetUser: u,
                                    ))),
                      ),
                    );
                  },
                ),
    );
  }
}
