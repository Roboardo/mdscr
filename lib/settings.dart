import 'package:shared_preferences/shared_preferences.dart';

const defaultWebSocketUrl = 'wss://echo.websocket.events';

class AppSettings {
  const AppSettings({required this.webSocketUrl});

  final String webSocketUrl;

  AppSettings copyWith({String? webSocketUrl}) {
    return AppSettings(webSocketUrl: webSocketUrl ?? this.webSocketUrl);
  }
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class SharedPreferencesSettingsRepository implements SettingsRepository {
  static const _webSocketUrlKey = 'websocket_url';

  @override
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppSettings(
      webSocketUrl: preferences.getString(_webSocketUrlKey) ?? defaultWebSocketUrl,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_webSocketUrlKey, settings.webSocketUrl);
  }
}

String? validateWebSocketUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasAuthority || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    return 'Enter a valid ws:// or wss:// address.';
  }
  return null;
}
