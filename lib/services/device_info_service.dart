import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';

/// Reports this device/app-version to the backend right after login, purely
/// so the admin CRM panel can show "who's on what phone/OS/app version" —
/// the app never reads this back. Best-effort: any failure is silently
/// swallowed, exactly like every other fire-and-forget telemetry call.
class DeviceInfoService {
  static Future<void> reportSession() async {
    try {
      String model = '', osVersion = '', platform = '';
      if (Platform.isAndroid) {
        final d = await DeviceInfoPlugin().androidInfo;
        model = '${d.manufacturer} ${d.model}'.trim();
        osVersion = 'Android ${d.version.release} (SDK ${d.version.sdkInt})';
        platform = 'android';
      } else if (Platform.isIOS) {
        final d = await DeviceInfoPlugin().iosInfo;
        model = d.utsname.machine;
        osVersion = 'iOS ${d.systemVersion}';
        platform = 'ios';
      }
      final pkg = await PackageInfo.fromPlatform();
      await ApiService.sendSessionInfo(
        deviceModel: model,
        osVersion: osVersion,
        appVersion: '${pkg.version}+${pkg.buildNumber}',
        platform: platform,
      );
    } catch (_) {}
  }
}
