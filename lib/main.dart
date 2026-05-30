import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'services/socket_service.dart';

const String API_URL = 'https://sigma-social-backend.onrender.com/api';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sigma Social',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: const Color(0xFFD4AF37),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFD4AF37),
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 5,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF333333), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          labelStyle: const TextStyle(color: Color(0xFFD4AF37)),
          hintStyle: TextStyle(color: Colors.grey[600]),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textTheme: TextTheme(
          displayLarge: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          titleLarge: const TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          bodyLarge: TextStyle(
            color: Colors.grey[300],
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
          ),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1A1A1A),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ===== LOGIN SCREEN =====
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  String message = '';

  Future<void> register() async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$API_URL/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': emailController.text,
          'username': emailController.text.split('@')[0],
          'password': passwordController.text,
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        setState(() => message = '✅ Registered! Now login');
        await Future.delayed(const Duration(seconds: 2));
        login();
      } else {
        setState(() => message = '❌ ${data['error']}');
      }
    } catch (e) {
      setState(() => message = '❌ Error: $e');
    }
    setState(() => isLoading = false);
  }

  Future<void> login() async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$API_URL/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': emailController.text,
          'password': passwordController.text,
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FeedScreen(user: data['data']['user']),
            ),
          );
        }
      } else {
        setState(() => message = '❌ ${data['error']}');
      }
    } catch (e) {
      setState(() => message = '❌ Error: $e');
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sigma Social')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('SIGMA SOCIAL',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 30),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(message),
              ),
            ElevatedButton(
              onPressed: isLoading ? null : login,
              child: Text(isLoading ? 'Loading...' : 'Login'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: isLoading ? null : register,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[700],
              ),
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}

// ===== FEED SCREEN =====
class FeedScreen extends StatefulWidget {
  final Map user;
  const FeedScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final postController = TextEditingController();
  final searchController = TextEditingController();
  List posts = [];
  List filteredPosts = [];
  Map<String, Map> usersMap = {};
  bool isLoading = false;
  late SocketService socketService;

  @override
  void initState() {
    super.initState();
    socketService = SocketService();
    socketService.connect(widget.user['id']);
    getPosts();
    searchController.addListener(filterPosts);
  }

  Future<void> getPosts() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('$API_URL/posts'));
      final data = jsonDecode(response.body);
      if (data['success']) {
        setState(() => posts = data['data'] ?? []);
        filteredPosts = posts;
        for (var post in posts) {
          if (!usersMap.containsKey(post['user_id'])) {
            getUserInfo(post['user_id']);
          }
        }
      }
    } catch (e) {
      print('Error: $e');
    }
    setState(() => isLoading = false);
  }

  Future<void> getUserInfo(String userId) async {
    try {
      final response = await http.get(Uri.parse('$API_URL/users/$userId'));
      final data = jsonDecode(response.body);
      if (data['success']) {
        setState(() {
          usersMap[userId] = data['data'];
        });
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  void filterPosts() {
    final query = searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => filteredPosts = posts);
    } else {
      setState(() {
        filteredPosts = posts.where((post) {
          final content = (post['content'] ?? '').toLowerCase();
          final username =
              (usersMap[post['user_id']]?['username'] ?? '').toLowerCase();
          return content.contains(query) || username.contains(query);
        }).toList();
      });
    }
  }

  Future<void> createPost() async {
    if (postController.text.isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse('$API_URL/posts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.user['id'],
          'content': postController.text,
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        postController.clear();
        getPosts();
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome ${widget.user['username']}!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatsScreen(user: widget.user),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(
                    user: widget.user,
                    isOwnProfile: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search posts or users...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37)),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          filterPosts();
                        },
                      )
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: postController,
                    decoration: const InputDecoration(
                      hintText: 'Share your thoughts...',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: createPost,
                  child: const Text('Post'),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredPosts.isEmpty
                    ? Center(
                        child: Text(
                          searchController.text.isEmpty
                              ? 'No posts yet'
                              : 'No posts found for "${searchController.text}"',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredPosts.length,
                        itemBuilder: (context, index) {
                          final post = filteredPosts[index];
                          final userInfo = usersMap[post['user_id']];
                          final username = userInfo != null
                              ? userInfo['username'] ?? 'User'
                              : 'Loading...';
                          return Card(
                            margin: const EdgeInsets.all(10),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProfileScreen(
                                            user: widget.user,
                                            targetUserId: post['user_id'],
                                            isOwnProfile: false,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      username,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD4AF37),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    post['content'],
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '❤️ ${post['likes_count']} likes',
                                    style: TextStyle(color: Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    postController.dispose();
    searchController.dispose();
    super.dispose();
  }
}

// ===== PROFILE SCREEN =====
class ProfileScreen extends StatefulWidget {
  final Map user;
  final String? targetUserId;
  final bool isOwnProfile;

  const ProfileScreen({
    Key? key,
    required this.user,
    this.targetUserId,
    this.isOwnProfile = true,
  }) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Map userProfile;
  List userPosts = [];
  bool isLoading = false;
  bool isEditing = false;
  bool isFollowing = false;
  bool isUploadingAvatar = false;

  late TextEditingController usernameController;
  late TextEditingController bioController;

  Future<void> pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null) return;

    setState(() => isUploadingAvatar = true);
    try {
      final bytes = await image.readAsBytes();
      final fileName = '${widget.user['id']}_avatar.jpg';

      final uploadResponse = await http.put(
        Uri.parse(
            'https://uvbyxkrtyjqrorxnckvw.supabase.co/storage/v1/object/avatars/$fileName'),
        headers: {
          'Authorization':
              'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV2Ynl4a3J0eWpxcm9yeG5ja3Z3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTg5MDM4NiwiZXhwIjoyMDk1NDY2Mzg2fQ.oP8PhoIqP8F6QJnKM4p-gujW_nfe12ZWsePg_Scc_8A',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: bytes,
      );

      if (uploadResponse.statusCode == 200 ||
          uploadResponse.statusCode == 201) {
        final avatarUrl =
            'https://uvbyxkrtyjqrorxnckvw.supabase.co/storage/v1/object/public/avatars/$fileName?t=${DateTime.now().millisecondsSinceEpoch}';

        await http.post(
          Uri.parse('$API_URL/users/${widget.user['id']}/update'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': userProfile['username'],
            'bio': userProfile['bio'] ?? '',
            'avatar_url': avatarUrl,
          }),
        );

        setState(() => userProfile['avatar_url'] = avatarUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Avatar updated!')),
        );
      }
    } catch (e) {
      print('Avatar upload error: $e');
    }
    setState(() => isUploadingAvatar = false);
  }

  @override
  void initState() {
    super.initState();
    if (widget.isOwnProfile) {
      userProfile = widget.user;
    } else {
      userProfile = {};
    }
    usernameController =
        TextEditingController(text: userProfile['username'] ?? '');
    bioController = TextEditingController(text: userProfile['bio'] ?? '');
    getUserProfile();
    getUserPosts();
    if (!widget.isOwnProfile) {
      checkFollowStatus();
    }
  }

  Future<void> getUserProfile() async {
    final userId =
        widget.isOwnProfile ? widget.user['id'] : widget.targetUserId;
    try {
      final response = await http.get(Uri.parse('$API_URL/users/$userId'));
      final data = jsonDecode(response.body);
      if (data['success']) {
        setState(() => userProfile = data['data']);
        usernameController.text = userProfile['username'] ?? '';
        bioController.text = userProfile['bio'] ?? '';
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> getUserPosts() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('$API_URL/posts'));
      final data = jsonDecode(response.body);
      if (data['success']) {
        final allPosts = data['data'] ?? [];
        final userId =
            widget.isOwnProfile ? widget.user['id'] : widget.targetUserId;
        setState(() {
          userPosts = allPosts.where((p) => p['user_id'] == userId).toList();
        });
      }
    } catch (e) {
      print('Error: $e');
    }
    setState(() => isLoading = false);
  }

  Future<void> checkFollowStatus() async {
    try {
      final response = await http.get(
        Uri.parse(
            '$API_URL/users/${widget.user['id']}/following/${widget.targetUserId}'),
      );
      final data = jsonDecode(response.body);
      setState(() => isFollowing = data['isFollowing'] ?? false);
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> toggleFollow() async {
    try {
      final endpoint = isFollowing ? 'unfollow' : 'follow';
      final response = await http.post(
        Uri.parse(
            '$API_URL/users/${widget.user['id']}/$endpoint/${widget.targetUserId}'),
        headers: {'Content-Type': 'application/json'},
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        setState(() {
          isFollowing = !isFollowing;
          if (isFollowing) {
            userProfile['followers_count'] =
                (userProfile['followers_count'] ?? 0) + 1;
          } else {
            userProfile['followers_count'] =
                (userProfile['followers_count'] ?? 1) - 1;
          }
        });
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> updateProfile() async {
    try {
      final response = await http.post(
        Uri.parse('$API_URL/users/${widget.user['id']}/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameController.text,
          'bio': bioController.text,
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        setState(() {
          isEditing = false;
          userProfile['username'] = usernameController.text;
          userProfile['bio'] = bioController.text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profile updated!')),
        );
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (widget.isOwnProfile && !isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => isEditing = true),
            )
          else if (widget.isOwnProfile && isEditing)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: updateProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: widget.isOwnProfile ? pickAndUploadAvatar : null,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37),
                            shape: BoxShape.circle,
                            image: userProfile['avatar_url'] != null
                                ? DecorationImage(
                                    image:
                                        NetworkImage(userProfile['avatar_url']),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: userProfile['avatar_url'] == null
                              ? const Icon(Icons.person,
                                  size: 50, color: Colors.black)
                              : null,
                        ),
                        if (widget.isOwnProfile)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD4AF37),
                                shape: BoxShape.circle,
                              ),
                              child: isUploadingAvatar
                                  ? const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.camera_alt,
                                      size: 18, color: Colors.black),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!isEditing)
                    Text(
                      userProfile['username'] ?? 'User',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    )
                  else
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                  const SizedBox(height: 10),
                  if (!isEditing)
                    Text(
                      userProfile['bio'] ?? 'No bio',
                      style: TextStyle(color: Colors.grey[400]),
                      textAlign: TextAlign.center,
                    )
                  else
                    TextField(
                      controller: bioController,
                      decoration: const InputDecoration(labelText: 'Bio'),
                      maxLines: 3,
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [
                        Text(userPosts.length.toString(),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37))),
                        const Text('Posts'),
                      ]),
                      Column(children: [
                        Text((userProfile['followers_count'] ?? 0).toString(),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37))),
                        const Text('Followers'),
                      ]),
                      Column(children: [
                        Text((userProfile['following_count'] ?? 0).toString(),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37))),
                        const Text('Following'),
                      ]),
                    ],
                  ),
                  if (!widget.isOwnProfile)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: toggleFollow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFollowing
                                  ? Colors.grey[700]
                                  : const Color(0xFFD4AF37),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 12),
                            ),
                            child: Text(
                              isFollowing ? 'Following ✓' : 'Follow +',
                              style: TextStyle(
                                  color: isFollowing
                                      ? Colors.white
                                      : Colors.black),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatDetailScreen(
                                    chat: {
                                      'id':
                                          '${widget.user['id']}_${widget.targetUserId}',
                                      'name': userProfile['username'],
                                    },
                                    user: widget.user,
                                    targetUser: userProfile,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 12),
                            ),
                            child: const Text('Message 💬',
                                style: TextStyle(color: Colors.black)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Posts',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : userPosts.isEmpty
                          ? const Text('No posts')
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: userPosts.length,
                              itemBuilder: (context, index) {
                                final post = userPosts[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(15),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(post['content'],
                                            style:
                                                const TextStyle(fontSize: 16)),
                                        const SizedBox(height: 10),
                                        Text('❤️ ${post['likes_count']} likes',
                                            style: TextStyle(
                                                color: Colors.grey[400])),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    bioController.dispose();
    super.dispose();
  }
}

// ===== CHATS SCREEN =====
class ChatsScreen extends StatefulWidget {
  final Map user;
  const ChatsScreen({Key? key, required this.user}) : super(key: key);

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List chats = [];
  bool isLoading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    getChats();
    // Автообновление списка чатов каждые 5 секунд
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) getChats();
    });
  }

  Future<void> getChats() async {
    try {
      final response = await http
          .get(Uri.parse('$API_URL/chats?userId=${widget.user['id']}'));
      final data = jsonDecode(response.body);
      if (data['success'] && mounted) {
        setState(() => chats = data['data'] ?? []);
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SelectUserScreen(user: widget.user),
                            ),
                          );
                        },
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: Color(0xFFD4AF37),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add,
                              size: 60, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Tap to start chatting',
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return Card(
                      margin: const EdgeInsets.all(10),
                      child: ListTile(
                        title: Text(chat['name'] ?? 'Chat ${index + 1}'),
                        subtitle: Text(chat['last_message'] ?? 'No messages'),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatDetailScreen(
                                chat: chat,
                                user: widget.user,
                                targetUser: {
                                  'id': chat['user1_id'] == widget.user['id']
                                      ? chat['user2_id']
                                      : chat['user1_id'],
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ===== SELECT USER SCREEN =====
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
    getUsers();
  }

  Future<void> getUsers() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('$API_URL/users'));
      final data = jsonDecode(response.body);
      if (data['success']) {
        final allUsers = data['data'] ?? [];
        setState(() {
          users = allUsers.where((u) => u['id'] != widget.user['id']).toList();
        });
      }
    } catch (e) {
      print('Error: $e');
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select User to Chat')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : users.isEmpty
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final targetUser = users[index];
                    return Card(
                      margin: const EdgeInsets.all(10),
                      child: ListTile(
                        title: Text(targetUser['username'] ?? 'User'),
                        subtitle: Text(targetUser['email'] ?? ''),
                        trailing: const Icon(Icons.message),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatDetailScreen(
                                chat: {
                                  'id':
                                      '${widget.user['id']}_${targetUser['id']}',
                                  'name': targetUser['username'],
                                },
                                user: widget.user,
                                targetUser: targetUser,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

// ===== CHAT DETAIL SCREEN =====
class ChatDetailScreen extends StatefulWidget {
  final Map chat;
  final Map user;
  final Map? targetUser;

  const ChatDetailScreen({
    Key? key,
    required this.chat,
    required this.user,
    this.targetUser,
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final messageController = TextEditingController();
  List messages = [];
  bool isLoading = false;
  String? correctChatId;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  // Сначала получаем правильный chat_id, потом загружаем сообщения
  Future<void> _initChat() async {
    setState(() => isLoading = true);
    try {
      final chatResponse = await http.post(
        Uri.parse('$API_URL/chats/get-or-create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user1_id': widget.user['id'],
          'user2_id': widget.targetUser?['id'] ??
              (widget.chat['user2_id'] ?? widget.chat['targetUserId']),
        }),
      );
      final chatData = jsonDecode(chatResponse.body);
      if (chatData['success']) {
        correctChatId = chatData['data']['id'];
        await getMessages();
        // Автообновление сообщений каждые 3 секунды
        _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
          if (mounted) getMessages();
        });
      }
    } catch (e) {
      print('Init chat error: $e');
    }
    setState(() => isLoading = false);
  }

  Future<void> getMessages() async {
    if (correctChatId == null) return;
    try {
      final response =
          await http.get(Uri.parse('$API_URL/messages/$correctChatId'));
      final data = jsonDecode(response.body);
      if (data['success'] && mounted) {
        setState(() => messages = data['data'] ?? []);
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> sendMessage() async {
    if (messageController.text.isEmpty || correctChatId == null) return;

    final messageText = messageController.text;
    messageController.clear();

    try {
      await http.post(
        Uri.parse('$API_URL/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': correctChatId,
          'sender_id': widget.user['id'],
          'content': messageText,
        }),
      );
      // Сразу обновляем сообщения после отправки
      await getMessages();
    } catch (e) {
      print('Send message error: $e');
      setState(() {
        messages.add({
          'sender_id': widget.user['id'],
          'content': messageText,
          'timestamp': DateTime.now().toString(),
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chat['name'] ?? 'Chat')),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(
                        child: Text('No messages yet. Start chatting!'))
                    : ListView.builder(
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          final isOwn =
                              message['sender_id'] == widget.user['id'];
                          return Align(
                            alignment: isOwn
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? const Color(0xFFD4AF37)
                                    : const Color(0xFF333333),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                message['content'],
                                style: TextStyle(
                                  color: isOwn ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration:
                        const InputDecoration(hintText: 'Type message...'),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: sendMessage,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    messageController.dispose();
    super.dispose();
  }
}
