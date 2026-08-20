import 'package:flutter_test/flutter_test.dart';
import 'package:signal_chat/settings.dart';

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
}
