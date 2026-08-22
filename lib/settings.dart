import 'package:shared_preferences/shared_preferences.dart';

import 'signal_dictionary.dart';

const defaultWebSocketUrl = 'wss://dscr-relay.dixonary.co.uk';
const dscrWebsiteHost = 'dscr.dixonary.co.uk';
const permanentBackgroundConnection = -1;

enum AppTheme { terminalDark, terminalLight }

class AppSettings {
  const AppSettings({
    required this.webSocketUrl,
    this.dictionary = const SignalDictionary.empty(),
    this.theme = AppTheme.terminalDark,
    this.preferredCallSign,
    this.backgroundConnectionGraceSeconds = 120,
    this.activeEncryptionKeys = const [],
  });

  final String webSocketUrl;
  final SignalDictionary dictionary;
  final AppTheme theme;
  final int? preferredCallSign;
  final int backgroundConnectionGraceSeconds;
  final List<int> activeEncryptionKeys;

  AppSettings copyWith({
    String? webSocketUrl,
    SignalDictionary? dictionary,
    AppTheme? theme,
    int? preferredCallSign,
    int? backgroundConnectionGraceSeconds,
    List<int>? activeEncryptionKeys,
    bool clearPreferredCallSign = false,
  }) {
    return AppSettings(
      webSocketUrl: webSocketUrl ?? this.webSocketUrl,
      dictionary: dictionary ?? this.dictionary,
      theme: theme ?? this.theme,
      preferredCallSign: clearPreferredCallSign
          ? null
          : preferredCallSign ?? this.preferredCallSign,
      backgroundConnectionGraceSeconds: backgroundConnectionGraceSeconds ??
          this.backgroundConnectionGraceSeconds,
      activeEncryptionKeys: activeEncryptionKeys ?? this.activeEncryptionKeys,
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
  static const _themeKey = 'theme';
  static const _preferredCallSignKey = 'preferred_call_sign';
  static const _backgroundConnectionGraceSecondsKey =
      'background_connection_grace_seconds';
  static const _activeEncryptionKeysKey = 'active_encryption_keys';

  @override
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedDictionary = preferences.getString(_dictionaryKey);
    SignalDictionary dictionary;
    try {
      dictionary = savedDictionary == null
          ? const SignalDictionary.empty()
          : SignalDictionary.fromStoredJsonString(savedDictionary);
    } on FormatException {
      dictionary = const SignalDictionary.empty();
    }
    if (savedDictionary != null && savedDictionary != dictionary.toJsonString()) {
      await preferences.setString(_dictionaryKey, dictionary.toJsonString());
    }
    return AppSettings(
      webSocketUrl: normalizeWebSocketUrl(
        preferences.getString(_webSocketUrlKey) ?? defaultWebSocketUrl,
      ),
      dictionary: dictionary,
      theme: switch (preferences.getString(_themeKey)) {
        'terminalLight' => AppTheme.terminalLight,
        _ => AppTheme.terminalDark,
      },
      preferredCallSign: preferences.getInt(_preferredCallSignKey),
      backgroundConnectionGraceSeconds:
          preferences.getInt(_backgroundConnectionGraceSecondsKey) ?? 120,
      activeEncryptionKeys: (preferences.getStringList(_activeEncryptionKeysKey) ??
              const [])
          .map(int.tryParse)
          .whereType<int>()
          .toList(),
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _webSocketUrlKey,
      normalizeWebSocketUrl(settings.webSocketUrl),
    );
    await preferences.setString(
        _dictionaryKey, settings.dictionary.toJsonString());
    await preferences.setString(_themeKey, settings.theme.name);
    if (settings.preferredCallSign == null) {
      await preferences.remove(_preferredCallSignKey);
    } else {
      await preferences.setInt(
        _preferredCallSignKey,
        settings.preferredCallSign!,
      );
    }
    await preferences.setInt(
      _backgroundConnectionGraceSecondsKey,
      settings.backgroundConnectionGraceSeconds,
    );
    await preferences.setStringList(
      _activeEncryptionKeysKey,
      settings.activeEncryptionKeys.map((key) => key.toString()).toList(),
    );
  }
}

String normalizeWebSocketUrl(String value) {
  final normalizedValue = value.trim();
  final uri = Uri.tryParse(normalizedValue);
  if (uri?.host.toLowerCase() == dscrWebsiteHost) {
    return defaultWebSocketUrl;
  }
  return normalizedValue;
}

String? validateWebSocketUrl(String? value) {
  final uri = Uri.tryParse(normalizeWebSocketUrl(value ?? ''));
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    return 'Enter a valid ws:// or wss:// address.';
  }
  return null;
}

String? validateCallSign(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final callSign = octalCallSignToDecimal(value);
  if (callSign == null || callSign < 1 || callSign > 4094) {
    return 'ENTER AN OCTAL NUMBER FROM 1 TO 7776.';
  }
  return null;
}

int? octalCallSignToDecimal(String value) {
  return int.tryParse(value.trim(), radix: 8);
}

String decimalCallSignToOctal(int value) {
  return value.toRadixString(8);
}
