import 'package:shared_preferences/shared_preferences.dart';

import 'signal_dictionary.dart';

const defaultWebSocketUrl = 'wss://echo.websocket.events';

class AppSettings {
  const AppSettings({
    required this.webSocketUrl,
    this.dictionary = const SignalDictionary.empty(),
  });

  final String webSocketUrl;
  final SignalDictionary dictionary;

  AppSettings copyWith({
    String? webSocketUrl,
    SignalDictionary? dictionary,
  }) {
    return AppSettings(
      webSocketUrl: webSocketUrl ?? this.webSocketUrl,
      dictionary: dictionary ?? this.dictionary,
    );
  }
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class SharedPreferencesSettingsRepository implements SettingsRepository {
  static const _webSocketUrlKey = 'websocket_url';
  static const _dictionaryKey = 'signal_dictionary';

  @override
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedDictionary = preferences.getString(_dictionaryKey);
    return AppSettings(
      webSocketUrl: preferences.getString(_webSocketUrlKey) ?? defaultWebSocketUrl,
      dictionary: savedDictionary == null
          ? const SignalDictionary.empty()
          : SignalDictionary.fromJsonString(savedDictionary),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_webSocketUrlKey, settings.webSocketUrl);
    await preferences.setString(_dictionaryKey, settings.dictionary.toJsonString());
  }
}

String? validateWebSocketUrl(String? value) {
  final trimmedValue = value?.trim() ?? '';
  final uri = Uri.tryParse(trimmedValue);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    return 'Enter a valid ws:// or wss:// address.';
  }
  return null;
}
