import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdscr/graphic_message.dart';
import 'package:mdscr/main.dart';
import 'package:mdscr/music_message.dart';
import 'package:mdscr/settings.dart';
import 'package:mdscr/signal_dictionary.dart';

void main() {
  test('terminal themes use monospaced typography and expected brightness', () {
    final darkTheme = terminalTheme(AppTheme.terminalDark);
    final lightTheme = terminalTheme(AppTheme.terminalLight);

    expect(darkTheme.brightness, Brightness.dark);
    expect(lightTheme.brightness, Brightness.light);
    expect(darkTheme.textTheme.bodyMedium?.fontFamily, 'monospace');
    expect(lightTheme.textTheme.bodyMedium?.fontFamily, 'monospace');
  });

  test('notification body translates unencrypted message signals', () {
    const dictionary = SignalDictionary({-1: 'HELLO'});
    final message = RelayMessage(callSign: 1, sequence: 1, signals: [-1, 42]);

    expect(notificationBodyForRelayMessage(message, dictionary), 'HELLO 42');
  });

  test('notification body does not expose encrypted signal contents', () {
    const dictionary = SignalDictionary({-1: 'HELLO'});
    final message = RelayMessage(
      callSign: 1,
      sequence: 1,
      signals: [signalEncryption, 123, -1],
    );

    expect(
      notificationBodyForRelayMessage(message, dictionary),
      'ENCRYPTED SIGNAL MESSAGE',
    );
  });

  test('formats message text and raw data for copying', () {
    const message = RelayMessage(callSign: 8, sequence: 12, signals: [-1, 42]);
    const dictionary = SignalDictionary({-1: 'HELLO'});

    expect(messageTextForClipboard(message, dictionary), 'HELLO 42');
    expect(rawMessageDataForClipboard(message), 'R,8,12,-1,42');
  });

  test('replaces the composer token at the cursor', () {
    const value = TextEditingValue(
      text: 'FIRST HELO LAST',
      selection: TextSelection.collapsed(offset: 8),
    );

    expect(messageTokenAtSelection(value), 'HELO');
    expect(
      replaceMessageTokenAtSelection(value, 'HELLO'),
      const TextEditingValue(
        text: 'FIRST HELLO LAST',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
  });

  test('finds an empty composer token', () {
    const value = TextEditingValue.empty;

    expect(messageTokenAtSelection(value), isEmpty);
  });

  test('creates music WAV data in a background isolate', () async {
    final wave = await compute(createMusicWaveFromData, [
      [0.0, .1, 440.0],
    ]);

    expect(wave.length, greaterThan(44));
    expect(wave.sublist(0, 4), [82, 73, 70, 70]);
  });

  testWidgets('music player uses a high-contrast lime play control', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MusicMessage(
            notes: [MusicNote(delay: 0, duration: .1, frequency: 440)],
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.style?.foregroundColor?.resolve({}), Colors.black);
  });

  testWidgets('3D graphic viewer provides reset controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GraphicViewerScreen(
          spheres: [
            GraphicSphere(x: 0, y: 0, z: 0, radius: 1, color: 32),
          ],
        ),
      ),
    );

    expect(find.text('3D VIEWER'), findsOneWidget);
    expect(find.byTooltip('RESET VIEW'), findsOneWidget);
  });
}
