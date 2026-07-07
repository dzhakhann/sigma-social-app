import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../theme/brutal_theme.dart';

/// GIF search (Tenor via backend). Returns the selected GIF's full URL via
/// Navigator.pop. No video — GIFs only.
class GifPickerScreen extends StatefulWidget {
  const GifPickerScreen({Key? key}) : super(key: key);
  @override
  State<GifPickerScreen> createState() => _GifPickerScreenState();
}

class _GifPickerScreenState extends State<GifPickerScreen> {
  final _ctrl = TextEditingController();
  List _gifs = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final data = await ApiService.searchGifs(q);
    if (mounted) setState(() { _gifs = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.k;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Выбрать GIF'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Поиск GIF…',
                prefixIcon: Icon(Icons.search, color: c.accent),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _gifs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'GIF пока недоступны.\nДобавьте ключ Giphy на сервере '
                      '(переменная GIPHY_API_KEY).',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.inkSoft, height: 1.4),
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _gifs.length,
                  itemBuilder: (_, i) {
                    final g = _gifs[i];
                    final preview = (g['preview'] ?? g['full']).toString();
                    final full = (g['full'] ?? '').toString();
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, full),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: preview,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: c.surface2),
                          errorWidget: (_, __, ___) =>
                              Container(color: c.surface2),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
