import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
  static String? _cachedVersion;

  static Future<String> getVersion() async {
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }
    final info = await PackageInfo.fromPlatform();
    _cachedVersion = info.version;
    return _cachedVersion!;
  }
}
