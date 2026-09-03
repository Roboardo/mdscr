import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'signal_dictionary.dart';

const defaultWebSocketUrl = 'wss://dscr-relay.dixonary.co.uk';
const dscrWebsiteHost = 'dscr.dixonary.co.uk';
const permanentBackgroundConnection = -1;

enum AppTheme { terminalDark, terminalLight }

class AppSettings {
  const AppSettings({
    required this.webSocketUrl,
    this.dictionaries = const {},
    SignalDictionary? dictionary,
    this.theme = AppTheme.terminalDark,
    this.preferredCallSign,
    this.backgroundConnectionGraceSeconds = 120,
    this.activeEncryptionKeys = const [],
  }) : _legacyDictionary = dictionary;

  final String webSocketUrl;
  final Map<String, SignalDictionary> dictionaries;
  final SignalDictionary? _legacyDictionary;
  SignalDictionary get dictionary =>
      dictionaries[normalizeWebSocketUrl(webSocketUrl)] ??
      _legacyDictionary ??
      const SignalDictionary.empty();
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
    final nextWebSocketUrl = normalizeWebSocketUrl(
      webSocketUrl ?? this.webSocketUrl,
    );
    return AppSettings(
      webSocketUrl: nextWebSocketUrl,
      dictionaries: dictionary == null
          ? dictionaries
          : {...dictionaries, nextWebSocketUrl: dictionary},
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
  static const _dictionariesKey = 'signal_dictionaries';
  static const _themeKey = 'theme';
  static const _preferredCallSignKey = 'preferred_call_sign';
  static const _backgroundConnectionGraceSecondsKey =
      'background_connection_grace_seconds';
  static const _activeEncryptionKeysKey = 'active_encryption_keys';

  @override
  Future<AppSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final webSocketUrl = normalizeWebSocketUrl(
      preferences.getString(_webSocketUrlKey) ?? defaultWebSocketUrl,
    );
    final savedDictionary = preferences.getString(_dictionaryKey);
    final dictionaries = _readDictionaries(
      preferences.getString(_dictionariesKey),
    );
    if (dictionaries.isEmpty && savedDictionary != null) {
      final dictionary = _readDictionary(savedDictionary);
      if (dictionary != null) {
        dictionaries[webSocketUrl] = dictionary;
      }
    }
    if (savedDictionary != null || preferences.containsKey(_dictionariesKey)) {
      await preferences.setString(_dictionariesKey, _encodeDictionaries(dictionaries));
    }
    return AppSettings(
      webSocketUrl: webSocketUrl,
      dictionaries: dictionaries,
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
      _dictionariesKey,
      _encodeDictionaries(settings.dictionaries),
    );
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

  Map<String, SignalDictionary> _readDictionaries(String? value) {
    if (value == null) {
      return {};
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        return {};
      }
      final dictionaries = <String, SignalDictionary>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) {
          continue;
        }
        final dictionary = _readDictionary(entry.value as String);
        if (dictionary != null) {
          dictionaries[normalizeWebSocketUrl(entry.key as String)] = dictionary;
        }
      }
      return dictionaries;
    } on FormatException {
      return {};
    }
  }

  SignalDictionary? _readDictionary(String value) {
    try {
      return SignalDictionary.fromStoredJsonString(value);
    } on FormatException {
      return null;
    }
  }

  String _encodeDictionaries(Map<String, SignalDictionary> dictionaries) => jsonEncode({
        for (final entry in dictionaries.entries)
          normalizeWebSocketUrl(entry.key): entry.value.toJsonString(),
      });
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
