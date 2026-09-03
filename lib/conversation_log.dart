import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';
import 'signal_dictionary.dart';

class ConversationLogEntry {
  const ConversationLogEntry({
    required this.receivedAt,
    required this.callSign,
    required this.sequence,
    required this.text,
    this.signals,
  });

  final DateTime receivedAt;
  final int callSign;
  final int sequence;
  final String text;
  final List<int>? signals;

  Map<String, Object> toJson() {
    final entrySignals = signals;
    return {
      'receivedAt': receivedAt.toIso8601String(),
      'callSign': callSign,
      'sequence': sequence,
      'text': text,
      if (entrySignals != null) 'signals': entrySignals,
    };
  }

  factory ConversationLogEntry.fromJson(Map<String, dynamic> json) {
    return ConversationLogEntry(
      receivedAt: DateTime.parse(json['receivedAt'] as String),
      callSign: json['callSign'] as int,
      sequence: json['sequence'] as int,
      text: json['text'] as String,
      signals: (json['signals'] as List<dynamic>?)?.cast<int>(),
    );
  }
}

String conversationLogText(
  ConversationLogEntry entry,
  SignalDictionary dictionary,
) => entry.signals == null ? entry.text : dictionary.formatSignals(entry.signals!);

String rawConversationLogData(ConversationLogEntry entry) =>
    'R,${entry.callSign},${entry.sequence},${entry.signals?.join(',') ?? entry.text}';

abstract interface class ConversationLogRepository {
  Future<List<ConversationLogEntry>> load();
  Future<void> add(
    RelayMessage message,
    DateTime receivedAt,
    SignalDictionary dictionary,
  );
  Future<void> clear();
}

class SharedPreferencesConversationLogRepository
    implements ConversationLogRepository {
  static const _logKey = 'conversation_log';
  static const _maximumEntries = 2000;
  Future<void> _writeQueue = Future.value();

  @override
  Future<List<ConversationLogEntry>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedLog = preferences.getString(_logKey);
    if (savedLog == null) {
      return const [];
    }
    try {
      final entries = (jsonDecode(savedLog) as List<dynamic>)
          .map(
            (entry) => ConversationLogEntry.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList();
      return List.unmodifiable(entries);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  @override
  Future<void> add(
    RelayMessage message,
    DateTime receivedAt,
    SignalDictionary dictionary,
  ) {
    _writeQueue = _writeQueue.then(
      (_) => _add(message, receivedAt, dictionary),
    );
    return _writeQueue;
  }

  Future<void> _add(
    RelayMessage message,
    DateTime receivedAt,
    SignalDictionary dictionary,
  ) async {
    final entries = (await load()).toList();
    final text = visibleSignalsForRelayMessage(message)
        .map(
          (signal) => dictionary.entries[signal] ?? signal.toString(),
        )
        .join(' ');
    entries.add(
      ConversationLogEntry(
        receivedAt: receivedAt,
        callSign: message.callSign,
        sequence: message.sequence,
        text: text,
        signals: List.unmodifiable(visibleSignalsForRelayMessage(message)),
      ),
    );
    final firstEntry = entries.length > _maximumEntries
        ? entries.length - _maximumEntries
        : 0;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _logKey,
      jsonEncode(entries.sublist(firstEntry).map((entry) => entry.toJson()).toList()),
    );
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_logKey);
  }
}