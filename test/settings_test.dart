import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chat/settings.dart';
import 'package:signal_chat/signal_dictionary.dart';

void main() {
  group('validateWebSocketUrl', () {
    test('accepts secure and local WebSocket addresses', () {
      expect(validateWebSocketUrl('wss://signals.example.org/chat'), isNull);
      expect(validateWebSocketUrl('ws://localhost:8080'), isNull);
    });

    test('rejects non-WebSocket or incomplete addresses', () {
      expect(validateWebSocketUrl('https://signals.example.org'), isNotNull);
      expect(validateWebSocketUrl('wss://'), isNotNull);
    });
  });

  group('SignalDictionary', () {
    test('imports negative keys and translates signal frames', () {
      final dictionary = SignalDictionary.fromJsonString(
        '{"wordDict":{"keys":[-1,-2],"values":["A","B"]}}',
      );

      expect(dictionary.entries, {-1: 'A', -2: 'B'});
      expect(translateSignalFrame('X,-1,-2,42', dictionary), 'X,A,B,42');
    });

    test('rejects invalid dictionaries and leaves malformed frames untouched', () {
      expect(
        () => SignalDictionary.fromJsonString(
          '{"wordDict":{"keys":[-1,2],"values":["A","B"]}}',
        ),
        throwsFormatException,
      );
      expect(
        translateSignalFrame('not a signal', const SignalDictionary.empty()),
        'not a signal',
      );
    });
  });
}
