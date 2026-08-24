import 'dart:convert';

const signalEncryption = -65535;
const signalEncryptionEnable = -65534;
const signalEncryptionDisable = -65533;
const signalEncryptionSkeleton = -65536;
const signalGraphic = -53;
const signalSphere = -52;
const signalMusic = -333;
const signalSong = -577;
const signalNote = -605003;
const signalOpen = -14;
const signalClose = -15;
const signalSeparator = -3;
const signalNegative = -1;
const signalDecimal = -10;

class GraphicSphere {
  const GraphicSphere({
    required this.x,
    required this.y,
    required this.z,
    required this.radius,
    required this.color,
  });

  final double x;
  final double y;
  final double z;
  final double radius;
  final int color;
}

class MusicNote {
  const MusicNote({
    required this.delay,
    required this.duration,
    required this.frequency,
  });

  final double delay;
  final double duration;
  final double frequency;
}

List<MusicNote>? parseMusicNotes(List<int> signals) {
  final musicSignals = signals
      .where((signal) => signal == signalMusic || signal == signalSong)
      .toList();
  if (musicSignals.length != 1) {
    return null;
  }

  final musicStart = signals.indexOf(musicSignals.single);
  if (musicStart + 1 >= signals.length ||
      signals[musicStart + 1] != signalOpen) {
    return null;
  }

  var current = musicStart + 2;
  final notes = <MusicNote>[];
  while (true) {
    if (current >= signals.length || signals[current++] != signalNote) {
      return null;
    }

    final values = <double>[];
    for (var index = 0; index < 3; index++) {
      final number = _consumeGraphicNumber(signals, current);
      if (number == null) {
        return null;
      }
      values.add(number.value);
      current = number.nextIndex;
      if (index < 2 &&
          (current >= signals.length ||
              signals[current++] != signalSeparator)) {
        return null;
      }
    }
    if (values[0] < 0 || values[1] <= 0 || values[2] <= 0) {
      return null;
    }
    notes.add(
      MusicNote(
        delay: values[0],
        duration: values[1],
        frequency: values[2],
      ),
    );

    if (current >= signals.length) {
      return null;
    }
    if (signals[current] == signalClose) {
      return List.unmodifiable(notes);
    }
    if (signals[current++] != signalSeparator || current >= signals.length) {
      return null;
    }
    if (signals[current] == signalClose) {
      return List.unmodifiable(notes);
    }
  }
}

List<GraphicSphere>? parseGraphicSpheres(List<int> signals) {
  if (signals.where((signal) => signal == signalGraphic).length != 1) {
    return null;
  }

  final imageStart = signals.indexOf(signalGraphic);
  if (imageStart + 1 >= signals.length ||
      signals[imageStart + 1] != signalOpen) {
    return null;
  }

  var current = imageStart + 2;
  final spheres = <GraphicSphere>[];
  while (true) {
    if (current >= signals.length || signals[current++] != signalSphere) {
      return null;
    }

    final coordinates = <double>[];
    for (var index = 0; index < 4; index++) {
      final number = _consumeGraphicNumber(signals, current);
      if (number == null) {
        return null;
      }
      coordinates.add(number.value);
      current = number.nextIndex;
      if (current >= signals.length || signals[current++] != signalSeparator) {
        return null;
      }
    }

    if (current >= signals.length ||
        signals[current] < 0 ||
        signals[current] > 64) {
      return null;
    }
    final color = signals[current++];
    spheres.add(
      GraphicSphere(
        x: coordinates[0],
        y: coordinates[1],
        z: coordinates[2],
        radius: coordinates[3],
        color: color,
      ),
    );

    if (current >= signals.length) {
      return null;
    }
    if (signals[current] == signalClose) {
      return List.unmodifiable(spheres);
    }
    if (signals[current++] != signalSeparator) {
      return null;
    }
  }
}

({double value, int nextIndex})? _consumeGraphicNumber(
  List<int> signals,
  int current,
) {
  var negative = false;
  if (current < signals.length && signals[current] == signalNegative) {
    negative = true;
    current++;
  }
  if (current >= signals.length || signals[current] < 0) {
    return null;
  }
  final whole = signals[current++];
  var value = whole.toDouble();
  if (current < signals.length && signals[current] == signalDecimal) {
    current++;
    if (current >= signals.length || signals[current] < 0) {
      return null;
    }
    final fraction = signals[current++];
    value = double.parse('$whole.$fraction');
  }
  return (value: negative ? -value : value, nextIndex: current);
}

enum SignalFormatMode {
  none(0),
  space(1),
  lineBreak(2),
  doubleLineBreak(3);

  const SignalFormatMode(this.value);

  final int value;

  static SignalFormatMode fromValue(Object? value, String field) {
    for (final mode in SignalFormatMode.values) {
      if (mode.value == value) {
        return mode;
      }
    }
    throw FormatException('"$field" must be an integer from 0 to 3.');
  }
}

class SignalDescription {
  const SignalDescription({
    required this.desc,
    required this.formatMode,
    required this.formatModeAfter,
    required this.breakOnDouble,
  });

  final String desc;
  final SignalFormatMode formatMode;
  final SignalFormatMode formatModeAfter;
  final bool breakOnDouble;

  Map<String, Object> toJson() => {
        'desc': desc,
        'formatMode': formatMode.value,
        'formatModeAfter': formatModeAfter.value,
        'breakOnDouble': breakOnDouble,
      };
}

class SignalDictionary {
  const SignalDictionary(
    this.entries, {
    this.descriptions = const {},
    this.id = 1,
    this.beforeUserDefaultMode = SignalFormatMode.space,
    this.afterUserDefaultMode = SignalFormatMode.space,
  });

  const SignalDictionary.empty()
      : entries = const {},
        descriptions = const {},
        id = 1,
        beforeUserDefaultMode = SignalFormatMode.space,
        afterUserDefaultMode = SignalFormatMode.space;

  final Map<int, String> entries;
  final Map<int, SignalDescription> descriptions;
  final int id;
  final SignalFormatMode beforeUserDefaultMode;
  final SignalFormatMode afterUserDefaultMode;

  factory SignalDictionary.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    _validateObject(
      decoded,
      'dictionary',
      const [
        'wordDict',
        'descDict',
        'id',
        'beforeUserDefaultMode',
        'afterUserDefaultMode',
      ],
    );
    final dictionary = decoded as Map<String, dynamic>;
    final wordDict = _validatedDictionary(dictionary['wordDict'], 'wordDict');
    final descDict = _validatedDictionary(dictionary['descDict'], 'descDict');
    final wordKeys = wordDict['keys'] as List;
    final wordValues = wordDict['values'] as List;
    final descKeys = descDict['keys'] as List;
    final descValues = descDict['values'] as List;
    if (wordKeys.length != wordValues.length ||
        descKeys.length != descValues.length ||
        wordKeys.length != descKeys.length) {
      throw const FormatException('Dictionary keys and values must have equal lengths.');
    }

    final entries = <int, String>{};
    final descriptions = <int, SignalDescription>{};
    for (var index = 0; index < wordKeys.length; index++) {
      final key = wordKeys[index];
      final value = wordValues[index];
      if (key is! int || key >= 0) {
        throw FormatException('Dictionary key ${index + 1} must be negative.');
      }
      if (descKeys[index] != key) {
        throw FormatException('"descDict.keys" must match "wordDict.keys".');
      }
      if (value is! String) {
        throw FormatException('Dictionary value ${index + 1} must be a string.');
      }
      if (entries.containsKey(key)) {
        throw FormatException('Dictionary key $key is repeated.');
      }
      entries[key] = value.toUpperCase();
      descriptions[key] = _parseDescription(descValues[index], index);
    }

    final id = dictionary['id'];
    if (id is! int) {
      throw const FormatException('"id" must be an integer.');
    }
    return SignalDictionary(
      Map.unmodifiable(entries),
      descriptions: Map.unmodifiable(descriptions),
      id: id,
      beforeUserDefaultMode: SignalFormatMode.fromValue(
        dictionary['beforeUserDefaultMode'],
        'beforeUserDefaultMode',
      ),
      afterUserDefaultMode: SignalFormatMode.fromValue(
        dictionary['afterUserDefaultMode'],
        'afterUserDefaultMode',
      ),
    );
  }

  factory SignalDictionary.fromStoredJsonString(String source) {
    try {
      return SignalDictionary.fromJsonString(source);
    } on FormatException {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 1 ||
          !decoded.containsKey('wordDict')) {
        rethrow;
      }
      final wordDict = _validatedDictionary(decoded['wordDict'], 'wordDict');
      final keys = wordDict['keys'] as List;
      final values = wordDict['values'] as List;
      if (keys.length != values.length) {
        throw const FormatException('Dictionary keys and values must have equal lengths.');
      }

      final entries = <int, String>{};
      final descriptions = <int, SignalDescription>{};
      for (var index = 0; index < keys.length; index++) {
        final key = keys[index];
        final value = values[index];
        if (key is! int || key >= 0 || value is! String || entries.containsKey(key)) {
          throw const FormatException('Legacy dictionary contains an invalid entry.');
        }
        final normalizedValue = value.toUpperCase();
        entries[key] = normalizedValue;
        descriptions[key] = SignalDescription(
          desc: normalizedValue,
          formatMode: SignalFormatMode.space,
          formatModeAfter: SignalFormatMode.space,
          breakOnDouble: false,
        );
      }
      return SignalDictionary(
        Map.unmodifiable(entries),
        descriptions: Map.unmodifiable(descriptions),
      );
    }
  }

  String toJsonString() {
    final keys = entries.keys.toList();
    return jsonEncode({
      'wordDict': {'keys': keys, 'values': entries.values.toList()},
      'descDict': {
        'keys': keys,
        'values': [
          for (final key in keys) _descriptionFor(key).toJson(),
        ],
      },
      'id': id,
      'beforeUserDefaultMode': beforeUserDefaultMode.value,
      'afterUserDefaultMode': afterUserDefaultMode.value,
    });
  }

  String displayTextForSignal(int signal) => entries[signal] ?? signal.toString();

  SignalDescription _descriptionFor(int signal) {
    return descriptions[signal] ??
        SignalDescription(
          desc: entries[signal] ?? signal.toString(),
          formatMode: beforeUserDefaultMode,
          formatModeAfter: afterUserDefaultMode,
          breakOnDouble: false,
        );
  }

  String formatSignals(Iterable<int> signals) {
    final values = signals.toList();
    if (values.isEmpty) {
      return '';
    }
    final buffer = StringBuffer(displayTextForSignal(values.first));
    for (var index = 1; index < values.length; index++) {
      buffer
        ..write(separatorBeforeSignal(values, index))
        ..write(displayTextForSignal(values[index]));
    }
    return buffer.toString();
  }

  String separatorBeforeSignal(List<int> signals, int index) {
    if (index < 1 || index >= signals.length) {
      throw RangeError.index(index, signals, 'index');
    }
    final breakAfterDouble = index >= 2 &&
        signals[index - 2] == signals[index - 1] &&
        signals[index - 1] < 0 &&
        descriptions[signals[index - 1]]?.breakOnDouble == true;
    return breakAfterDouble
        ? _separatorFor(SignalFormatMode.lineBreak)
        : separatorBetween(signals[index - 1], signals[index]);
  }

  String separatorBetween(int firstSignal, int secondSignal) {
    if (firstSignal > 0 && secondSignal > 0) {
      return ' ';
    }
    final before = secondSignal >= 0
      ? SignalFormatMode.none
      : descriptions[secondSignal]?.formatMode ?? beforeUserDefaultMode;
    final after = firstSignal >= 0
      ? SignalFormatMode.none
      : descriptions[firstSignal]?.formatModeAfter ?? afterUserDefaultMode;
    return _separatorFor(
      SignalFormatMode.values[after.index > before.index ? after.index : before.index],
    );
  }

  SignalDictionary withEntry(
    int signal,
    String value, {
    String? description,
    SignalFormatMode? formatMode,
    SignalFormatMode? formatModeAfter,
    bool? breakOnDouble,
  }) {
    if (signal >= 0) {
      throw ArgumentError.value(signal, 'signal', 'must be negative');
    }
    final current = _descriptionFor(signal);
    final updatedEntries = Map<int, String>.of(entries)
      ..[signal] = value.toUpperCase();
    final updatedDescriptions = Map<int, SignalDescription>.of(descriptions)
      ..[signal] = SignalDescription(
        desc: description ?? current.desc,
        formatMode: formatMode ?? current.formatMode,
        formatModeAfter: formatModeAfter ?? current.formatModeAfter,
        breakOnDouble: breakOnDouble ?? current.breakOnDouble,
      );
    return SignalDictionary(
      Map.unmodifiable(updatedEntries),
      descriptions: Map.unmodifiable(updatedDescriptions),
      id: id,
      beforeUserDefaultMode: beforeUserDefaultMode,
      afterUserDefaultMode: afterUserDefaultMode,
    );
  }

  SignalDictionary withoutEntry(int signal) {
    final updatedEntries = Map<int, String>.of(entries)..remove(signal);
    final updatedDescriptions = Map<int, SignalDescription>.of(descriptions)
      ..remove(signal);
    return SignalDictionary(
      Map.unmodifiable(updatedEntries),
      descriptions: Map.unmodifiable(updatedDescriptions),
      id: id,
      beforeUserDefaultMode: beforeUserDefaultMode,
      afterUserDefaultMode: afterUserDefaultMode,
    );
  }

  SignalDictionary withMissingEntriesFrom(SignalDictionary dictionary) {
    final updatedEntries = Map<int, String>.of(entries);
    final updatedDescriptions = Map<int, SignalDescription>.of(descriptions);
    for (final entry in dictionary.entries.entries) {
      updatedEntries.putIfAbsent(entry.key, () => entry.value);
      updatedDescriptions.putIfAbsent(
        entry.key,
        () => dictionary._descriptionFor(entry.key),
      );
    }
    return SignalDictionary(
      Map.unmodifiable(updatedEntries),
      descriptions: Map.unmodifiable(updatedDescriptions),
      id: id,
      beforeUserDefaultMode: beforeUserDefaultMode,
      afterUserDefaultMode: afterUserDefaultMode,
    );
  }

  List<MapEntry<int, String>> matchingEntries(String query) {
    final normalizedQuery = query.toUpperCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final matches = entries.entries
        .map(
          (entry) => (
            entry: entry,
            score: _matchScore(entry.value, normalizedQuery),
          ),
        )
        .where((match) => match.score != null)
        .toList()
      ..sort((a, b) {
        final scoreComparison = a.score!.compareTo(b.score!);
        return scoreComparison != 0
            ? scoreComparison
            : a.entry.value.compareTo(b.entry.value);
      });
    return List.unmodifiable(matches.map((match) => match.entry));
  }

  int? _matchScore(String word, String query) {
    if (word.startsWith(query)) {
      return 0;
    }
    if (word.contains(query)) {
      return 1;
    }

    var queryIndex = 0;
    var gaps = 0;
    for (var wordIndex = 0; wordIndex < word.length; wordIndex++) {
      if (word[wordIndex] == query[queryIndex]) {
        queryIndex++;
        if (queryIndex == query.length) {
          return 2 + gaps;
        }
      } else if (queryIndex > 0) {
        gaps++;
      }
    }
    return null;
  }

  List<int>? encodeMessage(String message) {
    final words = message.trim().toUpperCase().split(RegExp(r'\s+'));
    if (words.length == 1 && words.single.isEmpty) {
      return const [];
    }
    final signalsByWord = {
      for (final entry in entries.entries) entry.value: entry.key,
    };
    final signals = <int>[];
    for (final word in words) {
      if (word.startsWith('|-')) {
        final negativeSignal = _parseExplicitNegativeSignal(word);
        if (negativeSignal == null) {
          return null;
        }
        signals.add(negativeSignal);
        continue;
      }
      final numericSignal = _parseNumericSignal(word);
      if (numericSignal != null) {
        signals.add(numericSignal);
        continue;
      }
      final signal = signalsByWord[word];
      if (signal != null) {
        signals.add(signal);
        continue;
      }
      final splitSignals = _splitConcatenatedWords(word, signalsByWord);
      if (splitSignals == null) {
        return null;
      }
      signals.addAll(splitSignals);
    }
    return List.unmodifiable(signals);
  }

  List<int>? _splitConcatenatedWords(
    String word,
    Map<String, int> signalsByWord,
  ) {
    final dictionaryWords = signalsByWord.keys
        .where(
          (dictionaryWord) =>
              dictionaryWord.isNotEmpty &&
              !dictionaryWord.contains(RegExp(r'\s+')),
        )
        .toList()
      ..sort((a, b) {
        final lengthComparison = b.length.compareTo(a.length);
        return lengthComparison != 0 ? lengthComparison : a.compareTo(b);
      });
    final matches = List<List<int>?>.filled(word.length + 1, null)
      ..[word.length] = const [];

    for (var start = word.length - 1; start >= 0; start--) {
      for (final dictionaryWord in dictionaryWords) {
        if (!word.startsWith(dictionaryWord, start)) {
          continue;
        }
        final remainder = matches[start + dictionaryWord.length];
        if (remainder != null) {
          matches[start] = [signalsByWord[dictionaryWord]!, ...remainder];
          break;
        }
      }
      if (matches[start] != null || !_isDigit(word.codeUnitAt(start))) {
        continue;
      }
      for (var end = word.length; end > start; end--) {
        final signal = _parseNumericSignal(word.substring(start, end));
        final remainder = matches[end];
        if (signal != null && remainder != null) {
          matches[start] = [signal, ...remainder];
          break;
        }
      }
    }
    final result = matches.first;
    return result == null || result.length < 2 ? null : result;
  }

  bool _isDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

  int? _parseNumericSignal(String word) {
    final signal = int.tryParse(word);
    return signal != null && signal >= 0 ? signal : null;
  }

  int? _parseExplicitNegativeSignal(String word) {
    final signal = int.tryParse(word.substring(1));
    return signal != null && signal < 0 ? signal : null;
  }
}

void _validateObject(Object? value, String name, List<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.length != fields.length ||
      fields.any((field) => !value.containsKey(field))) {
    throw FormatException('"$name" does not match the dictionary schema.');
  }
}

Map<String, dynamic> _validatedDictionary(Object? value, String name) {
  _validateObject(value, name, const ['keys', 'values']);
  final dictionary = value! as Map<String, dynamic>;
  if (dictionary['keys'] is! List || dictionary['values'] is! List) {
    throw FormatException('"$name.keys" and "$name.values" must be arrays.');
  }
  return dictionary;
}

SignalDescription _parseDescription(Object? value, int index) {
  _validateObject(
    value,
    'descDict.values[${index + 1}]',
    const ['desc', 'formatMode', 'formatModeAfter', 'breakOnDouble'],
  );
  final description = value! as Map<String, dynamic>;
  if (description['desc'] is! String || description['breakOnDouble'] is! bool) {
    throw FormatException('Description ${index + 1} has invalid field types.');
  }
  return SignalDescription(
    desc: description['desc'] as String,
    formatMode: SignalFormatMode.fromValue(
      description['formatMode'],
      'descDict.values[${index + 1}].formatMode',
    ),
    formatModeAfter: SignalFormatMode.fromValue(
      description['formatModeAfter'],
      'descDict.values[${index + 1}].formatModeAfter',
    ),
    breakOnDouble: description['breakOnDouble'] as bool,
  );
}

String _separatorFor(SignalFormatMode mode) => switch (mode) {
      SignalFormatMode.none => '',
      SignalFormatMode.space => ' ',
      SignalFormatMode.lineBreak => '\n',
      SignalFormatMode.doubleLineBreak => '\n\n',
    };

class RelayMessage {
  const RelayMessage({
    required this.callSign,
    required this.sequence,
    required this.signals,
  });

  final int callSign;
  final int sequence;
  final List<int> signals;
}

String relayMessageId(RelayMessage message) =>
    '${message.callSign}:${message.sequence}';

bool isEncryptedRelayMessage(RelayMessage message) {
  return message.signals.isNotEmpty &&
      message.signals.first == signalEncryption;
}

int? encryptionKeyForRelayMessage(RelayMessage message) {
  if (!isEncryptedRelayMessage(message) || message.signals.length < 2) {
    return null;
  }
  return message.signals[1];
}

List<int> visibleSignalsForRelayMessage(RelayMessage message) {
  return isEncryptedRelayMessage(message)
      ? List.unmodifiable(message.signals.skip(2))
      : message.signals;
}

RelayMessage? parseRelayMessage(String frame) {
  final parts = frame.split(',');
  if (parts.length < 4 || parts.first != 'R') {
    return null;
  }

  final values = parts.skip(1).map(int.tryParse).toList();
  if (values.any((value) => value == null)) {
    return null;
  }
  return RelayMessage(
    callSign: values[0]!,
    sequence: values[1]!,
    signals: List.unmodifiable(values.skip(2).cast<int>()),
  );
}

int? parseCallSignAssignment(String frame) {
  final parts = frame.split(',');
  if (parts.length != 2 || parts.first != 'K') {
    return null;
  }
  return int.tryParse(parts.last);
}

List<int>? parseActiveCallSigns(String frame) {
  final parts = frame.split(',');
  if (parts.first != 'C') {
    return null;
  }
  final callSigns = parts.skip(1).map(int.tryParse).toList();
  if (callSigns.any((callSign) => callSign == null)) {
    return null;
  }
  return List.unmodifiable(callSigns.cast<int>());
}
