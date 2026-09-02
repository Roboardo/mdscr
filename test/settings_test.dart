import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdscr/settings.dart';
import 'package:mdscr/signal_dictionary.dart';

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

    test('uses the DSCR relay as the default', () {
      expect(defaultWebSocketUrl, 'wss://dscr-relay.dixonary.co.uk');
      expect(
        normalizeWebSocketUrl('wss://dscr.dixonary.co.uk'),
        defaultWebSocketUrl,
      );
    });

    test('defaults to the dark terminal theme', () {
      const settings = AppSettings(webSocketUrl: defaultWebSocketUrl);

      expect(settings.theme, AppTheme.terminalDark);
      expect(settings.backgroundConnectionGraceSeconds, 120);
      expect(settings.activeEncryptionKeys, isEmpty);
      expect(
        settings.copyWith(theme: AppTheme.terminalLight).theme,
        AppTheme.terminalLight,
      );
      expect(
        settings
            .copyWith(backgroundConnectionGraceSeconds: 300)
            .backgroundConnectionGraceSeconds,
        300,
      );
      expect(
        settings
            .copyWith(
              backgroundConnectionGraceSeconds: permanentBackgroundConnection,
            )
            .backgroundConnectionGraceSeconds,
        permanentBackgroundConnection,
      );
      expect(
        settings.copyWith(activeEncryptionKeys: [42, 99]).activeEncryptionKeys,
        [42, 99],
      );
    });

    test('accepts an optional octal callsign up to decimal 4094', () {
      expect(validateCallSign(''), isNull);
      expect(validateCallSign('1'), isNull);
      expect(validateCallSign('7776'), isNull);
      expect(octalCallSignToDecimal('3415'), 1805);
      expect(decimalCallSignToOctal(1805), '3415');
      expect(validateCallSign('0'), isNotNull);
      expect(validateCallSign('7777'), isNotNull);
      expect(validateCallSign('8'), isNotNull);
    });
  });

  group('SignalDictionary', () {
    test('parses MUSIC note payloads as delay, duration, and frequency', () {
      final notes = parseMusicNotes([
        -333, -14, -605003, 0, -10, 200, -3, 0, -10, 200, -3, 392, -3,
        -605003, 0, -10, 200, -3, 0, -10, 200, -3, 392, -15,
      ]);

      expect(notes, hasLength(2));
      expect(notes!.first.delay, .2 * musicSecond);
      expect(notes.first.duration, .2 * musicSecond);
      expect(notes.first.frequency, 392);
      expect(parseMusicNotes([-333, -14, -605003, 0, -3, 1, -3, 0, -15]),
          isNull);
    });

    test('parses duration-only structured MUSIC notes as rests', () {
      final notes = parseMusicNotes([
        -333, -14, -14, -605003, -3, 1, -3, -122, -605003, -3, 1,
        -3, 440, -15, -15,
      ]);

      expect(notes, hasLength(1));
      expect(notes!.single.delay, musicSecond);
      expect(notes.single.frequency, 440);
    });

    test('parses the supplied structured Tetris MUSIC stream', () {
      final signals = File('music-sample')
          .readAsStringSync()
          .trim()
          .split(RegExp(r'\s+'))
          .map(int.parse)
          .toList();

      final notes = parseMusicNotes(signals);
      expect(notes, isNotNull);
      expect(notes!.length, greaterThan(100));
      expect(notes.last.delay, greaterThan(30));
    });

    test('parses MFDS graphic sphere payloads', () {
      final spheres = parseGraphicSpheres([
        -53,
        -14,
        -52,
        -1,
        2,
        -10,
        5,
        -3,
        3,
        -3,
        4,
        -3,
        2,
        -10,
        5,
        -3,
        32,
        -15,
      ]);

      expect(spheres, hasLength(1));
      expect(spheres!.single.x, -2.5);
      expect(spheres.single.y, 3);
      expect(spheres.single.z, 4);
      expect(spheres.single.radius, 2.5);
      expect(spheres.single.color, 32);
      expect(parseGraphicSpheres([-53, -14, -52, 1, -15]), isNull);
    });

    test('imports and updates negative signal entries', () {
      final dictionary = SignalDictionary.fromJsonString(
        '{"wordDict":{"keys":[-1,-2],"values":["A","word"]},'
        '"descDict":{"keys":[-1,-2],"values":['
        '{"desc":"A","formatMode":1,"formatModeAfter":1,"breakOnDouble":false},'
        '{"desc":"word","formatMode":1,"formatModeAfter":1,"breakOnDouble":false}]},'
        '"id":1,"beforeUserDefaultMode":1,"afterUserDefaultMode":1}',
      );

      expect(dictionary.entries, {-1: 'A', -2: 'WORD'});
      expect(
        dictionary.withEntry(-3, 'new word').entries,
        {-1: 'A', -2: 'WORD', -3: 'NEW WORD'},
      );
      expect(dictionary.withoutEntry(-1).entries, {-2: 'WORD'});
      final matches = dictionary.matchingEntries('wo');
      expect(matches, hasLength(1));
      expect(matches.single.key, -2);
      expect(matches.single.value, 'WORD');
      expect(dictionary.encodeMessage('A WORD'), [-1, -2]);
      expect(dictionary.encodeMessage('AWORD'), [-1, -2]);
      expect(dictionary.encodeMessage('A 0 42 |-999'), [-1, 0, 42, -999]);
      expect(dictionary.encodeMessage('-999'), isNull);
      expect(
        dictionary.withEntry(-3, '|-0').encodeMessage('|-0'),
        isNull,
      );
      expect(dictionary.encodeMessage('UNKNOWN'), isNull);
    });

    test('ranks prefix suggestions before fuzzy matches', () {
      final dictionary = SignalDictionary.fromJsonString(
        '{"wordDict":{"keys":[-1,-2,-3],"values":["SHELL","HELLO","HILLO"]},'
        '"descDict":{"keys":[-1,-2,-3],"values":['
        '{"desc":"SHELL","formatMode":1,"formatModeAfter":1,"breakOnDouble":false},'
        '{"desc":"HELLO","formatMode":1,"formatModeAfter":1,"breakOnDouble":false},'
        '{"desc":"HILLO","formatMode":1,"formatModeAfter":1,"breakOnDouble":false}]},'
        '"id":1,"beforeUserDefaultMode":1,"afterUserDefaultMode":1}',
      );

      expect(
        dictionary.matchingEntries('HE').map((entry) => entry.value),
        ['HELLO', 'SHELL'],
      );
      expect(
        dictionary.matchingEntries('HLO').map((entry) => entry.value),
        ['HELLO', 'HILLO'],
      );
    });

    test('encodes punctuation-only dictionary entries', () {
      final dictionary = SignalDictionary.fromJsonString(
        '{"wordDict":{"keys":[-1,-2],"values":[",","WORD"]},'
        '"descDict":{"keys":[-1,-2],"values":['
        '{"desc":",","formatMode":1,"formatModeAfter":1,"breakOnDouble":false},'
        '{"desc":"WORD","formatMode":1,"formatModeAfter":1,"breakOnDouble":false}]},'
        '"id":1,"beforeUserDefaultMode":1,"afterUserDefaultMode":1}',
      );

      expect(dictionary.encodeMessage(','), [-1]);
      expect(dictionary.encodeMessage(', WORD'), [-1, -2]);
    });

    test('splits concatenated dictionary words before sending', () {
      final dictionary = SignalDictionary.fromJsonString(
        '{"wordDict":{"keys":[-1,-2,-3],"values":["HELLO","WORLD","NOW"]},'
        '"descDict":{"keys":[-1,-2,-3],"values":['
        '{"desc":"HELLO","formatMode":1,"formatModeAfter":1,"breakOnDouble":false},'
        '{"desc":"WORLD","formatMode":1,"formatModeAfter":1,"breakOnDouble":false},'
        '{"desc":"NOW","formatMode":1,"formatModeAfter":1,"breakOnDouble":false}]},'
        '"id":1,"beforeUserDefaultMode":1,"afterUserDefaultMode":1}',
      );

      expect(dictionary.encodeMessage('HELLOWORLDNOW'), [-1, -2, -3]);
      expect(dictionary.encodeMessage('HELLO123'), [-1, 123]);
      expect(dictionary.encodeMessage('HELLOTHERE'), isNull);
    });

    test('round-trips descriptions and uses the largest boundary format', () {
      final dictionary = SignalDictionary.fromJsonString(
        '{"wordDict":{"keys":[-1,-2,-3],"values":["A","B","C"]},'
        '"descDict":{"keys":[-1,-2,-3],"values":['
        '{"desc":"alpha","formatMode":0,"formatModeAfter":2,"breakOnDouble":false},'
        '{"desc":"beta","formatMode":1,"formatModeAfter":0,"breakOnDouble":true},'
        '{"desc":"gamma","formatMode":3,"formatModeAfter":0,"breakOnDouble":false}]},'
        '"id":7,"beforeUserDefaultMode":1,"afterUserDefaultMode":1}',
      );

      expect(dictionary.formatSignals([-1, -2, -3]), 'A\nB\n\nC');
      expect(dictionary.formatSignals([-2, -2]), 'BB');
      expect(dictionary.formatSignals([-2, -2, -1]), 'BB\nA');
      expect(dictionary.formatSignals([-1, -1]), 'AA');
      expect(dictionary.formatSignals([-2, 42]), 'B42');
      expect(dictionary.formatSignals([42, 43]), '42 43');
      final restored = SignalDictionary.fromJsonString(dictionary.toJsonString());
      expect(restored.id, 7);
      expect(restored.descriptions[-2]!.desc, 'beta');
      expect(restored.descriptions[-2]!.breakOnDouble, isTrue);
      expect(restored.formatSignals([-1, -2, -3]), 'A\nB\n\nC');
    });

    test('parses relay messages into call sign, sequence, and signals', () {
      expect(
        parseRelayMessage(
          'R,2058,83,-531401,-100,-14,-165,-170,-15,-30,-14,-166,-169,-15',
        ),
        isA<RelayMessage>()
            .having((message) => message.callSign, 'call sign', 2058)
            .having((message) => message.sequence, 'sequence', 83)
            .having(
          (message) => message.signals,
          'signals',
          [-531401, -100, -14, -165, -170, -15, -30, -14, -166, -169, -15],
        ),
      );
    });

    test('uses callsign and sequence as the relay message identity', () {
      final first = parseRelayMessage('R,2058,83,-1')!;
      final replay = parseRelayMessage('R,2058,83,-1')!;
      final next = parseRelayMessage('R,2058,84,-1')!;

      expect(relayMessageId(replay), relayMessageId(first));
      expect(relayMessageId(next), isNot(relayMessageId(first)));
    });

    test('rejects invalid dictionaries and non-relay frames', () {
      expect(
        () => SignalDictionary.fromJsonString(
          '{"wordDict":{"keys":[-1,2],"values":["A","B"]}}',
        ),
        throwsFormatException,
      );
      expect(parseRelayMessage('not a signal'), isNull);
      expect(parseCallSignAssignment('K,2058'), 2058);
      expect(parseCallSignAssignment('R,2058'), isNull);
      expect(parseActiveCallSigns('C,12,34'), [12, 34]);
      expect(parseActiveCallSigns('C,NOT_A_CALLSIGN'), isNull);
    });
  });
}
