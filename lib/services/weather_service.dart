import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Weather via 100% free, key-less, commercial-friendly APIs — nothing is
/// stored on our server or DB. Location is resolved by IP (no GPS permission),
/// then Open-Meteo returns the forecast. Cached on device for 30 minutes.
///
/// Sources:
///  · ipwho.is  — free IP geolocation, HTTPS, commercial use allowed, no key.
///  · open-meteo.com — free weather API, commercial use allowed, no key.
class WeatherService {
  static const _cacheKey = 'weather_cache_v1';
  static const _cacheTtl = Duration(minutes: 30);

  static Future<Map?> get({bool force = false}) async {
    final p = await SharedPreferences.getInstance();
    if (!force) {
      final raw = p.getString(_cacheKey);
      if (raw != null) {
        try {
          final m = jsonDecode(raw) as Map;
          final ts = DateTime.tryParse(m['_ts'] ?? '');
          if (ts != null && DateTime.now().difference(ts) < _cacheTtl) {
            return m;
          }
        } catch (_) {}
      }
    }
    try {
      // 1) Approx location by IP (no GPS permission needed).
      final geoR = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 8));
      final geo = jsonDecode(geoR.body) as Map;
      final lat = geo['latitude'];
      final lon = geo['longitude'];
      final city = (geo['city'] ?? geo['region'] ?? '').toString();
      if (lat == null || lon == null) return _cached(p);

      // 2) Current + 7-day forecast from Open-Meteo.
      final url =
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
          '&current=temperature_2m,weather_code'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min'
          '&timezone=auto&forecast_days=7';
      final wR =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final w = jsonDecode(wR.body) as Map;
      final cur = w['current'] as Map;
      final daily = w['daily'] as Map;
      final codes = (daily['weather_code'] as List);
      final maxs = (daily['temperature_2m_max'] as List);
      final mins = (daily['temperature_2m_min'] as List);
      final times = (daily['time'] as List);

      final result = {
        '_ts': DateTime.now().toIso8601String(),
        'city': city,
        'temp': (cur['temperature_2m'] as num).round(),
        'code': (cur['weather_code'] as num).toInt(),
        'days': List.generate(times.length, (i) => {
              'date': times[i],
              'code': (codes[i] as num).toInt(),
              'max': (maxs[i] as num).round(),
              'min': (mins[i] as num).round(),
            }),
      };
      await p.setString(_cacheKey, jsonEncode(result));
      return result;
    } catch (_) {
      return _cached(p);
    }
  }

  static Map? _cached(SharedPreferences p) {
    final raw = p.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map;
    } catch (_) {
      return null;
    }
  }

  // WMO weather code → emoji + short label key.
  static ({String emoji, String key}) describe(int code) {
    if (code == 0) return (emoji: '☀️', key: 'wClear');
    if (code <= 2) return (emoji: '🌤️', key: 'wPartly');
    if (code == 3) return (emoji: '☁️', key: 'wCloudy');
    if (code <= 48) return (emoji: '🌫️', key: 'wFog');
    if (code <= 57) return (emoji: '🌦️', key: 'wDrizzle');
    if (code <= 67) return (emoji: '🌧️', key: 'wRain');
    if (code <= 77) return (emoji: '❄️', key: 'wSnow');
    if (code <= 82) return (emoji: '🌧️', key: 'wRain');
    if (code <= 86) return (emoji: '🌨️', key: 'wSnow');
    return (emoji: '⛈️', key: 'wStorm');
  }

  // Short weekday label (Mon/Tue…) from an ISO date, localized-ish.
  static String weekday(String iso, String lang) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const ru = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final list = lang == 'ru' ? ru : en;
    return list[d.weekday - 1];
  }
}
