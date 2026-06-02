import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../constants.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool isLoading = false;
  String message = '';

  Future<void> _login() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
    setState(() { isLoading = true; message = ''; });
    try {
      final data = await ApiService.login(emailCtrl.text, passCtrl.text);
      if (data['success'] == true) {
        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(
              builder: (_) => MainScreen(user: data['data']['user'])));
        }
      } else {
        setState(() => message = '❌ ${data['error']}');
      }
    } catch (e) {
      setState(() => message = '❌ $e');
    }
    setState(() => isLoading = false);
  }

  Future<void> _register() async {
    if (emailCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
    setState(() { isLoading = true; message = ''; });
    try {
      final data = await ApiService.register(emailCtrl.text, passCtrl.text);
      if (data['success'] == true) {
        setState(() => message = '✅ Registered!');
        await Future.delayed(const Duration(milliseconds: 500));
        _login();
      } else {
        setState(() => message = '❌ ${data['error']}');
      }
    } catch (e) {
      setState(() => message = '❌ $e');
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('SIGMA',
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: kGold,
                    letterSpacing: 8)),
            const Text('SOCIAL',
                style: TextStyle(fontSize: 14, letterSpacing: 6, color: Colors.grey)),
            const SizedBox(height: 50),
            TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
            const SizedBox(height: 16),
            TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
            const SizedBox(height: 8),
            if (message.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(message, style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: isLoading ? null : _login,
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('Login')),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: isLoading ? null : _register,
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kGold),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Register',
                      style: TextStyle(color: kGold))),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }
}
