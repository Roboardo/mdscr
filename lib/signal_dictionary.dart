import 'dart:convert';

class SignalDictionary {
  const SignalDictionary(this.entries);

  const SignalDictionary.empty() : entries = const {};

  final Map<int, String> entries;

  factory SignalDictionary.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The dictionary must be a JSON object.');
    }

    final wordDict = decoded['wordDict'];
    if (wordDict is! Map<String, dynamic>) {
      throw const FormatException('Missing the "wordDict" object.');
    }

    final keys = wordDict['keys'];
    final values = wordDict['values'];
    if (keys is! List || values is! List || keys.length != values.length) {
      throw const FormatException(
        '"wordDict.keys" and "wordDict.values" must be lists of equal length.',
      );
    }

    final entries = <int, String>{};
    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      final value = values[index];
      if (key is! int || key >= 0) {
        throw FormatException('Dictionary key ${index + 1} must be negative.');
      }
      if (value is! String) {
        throw FormatException('Dictionary value ${index + 1} must be a string.');
      }
      if (entries.containsKey(key)) {
        throw FormatException('Dictionary key $key is repeated.');
      }
      entries[key] = value;
    }
    return SignalDictionary(Map.unmodifiable(entries));
  }

  String toJsonString() {
    return jsonEncode({
      'wordDict': {
        'keys': entries.keys.toList(),
        'values': entries.values.toList(),
      },
    });
  }
}

String translateSignalFrame(String frame, SignalDictionary dictionary) {
  final parts = frame.split(',');
  if (parts.length < 2 || !RegExp(r'^[A-Za-z]$').hasMatch(parts.first)) {
    return frame;
  }

  final translatedValues = <String>[];
  for (final rawValue in parts.skip(1)) {
    final value = int.tryParse(rawValue);
    if (value == null) {
      return frame;
    }
    translatedValues.add(
      value < 0 ? dictionary.entries[value] ?? value.toString() : value.toString(),
    );
  }
  return '${parts.first},${translatedValues.join(',')}';
}
