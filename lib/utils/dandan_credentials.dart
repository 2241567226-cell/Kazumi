import 'package:kazumi/services/storage/storage.dart';

// DanDanPlay API credentials for the client signature flow.
// Release/PR CI injects them via --dart-define=DANDANAPI_APPID / DANDANAPI_KEY.
const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};

/// 返回当前生效的弹弹play凭证：
/// 优先使用用户在「设置 -> 弹幕设置」中填写的 AppId / AppSecret，
/// 未填写时使用打包时注入的值。
Map<String, String> resolveDandanCredentials() {
  try {
    final id = GStorage.getSetting<String>(SettingsKeys.dandanAppId).trim();
    final secret =
        GStorage.getSetting<String>(SettingsKeys.dandanAppSecret).trim();
    if (id.isNotEmpty && secret.isNotEmpty) {
      return {'id': id, 'value': secret};
    }
  } catch (_) {}
  return dandanCredentials;
}

bool hasDandanCredentials() {
  final c = resolveDandanCredentials();
  return (c['id'] ?? '').isNotEmpty && (c['value'] ?? '').isNotEmpty;
}
