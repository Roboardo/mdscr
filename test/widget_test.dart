import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdscr/graphic_message.dart';
import 'package:mdscr/main.dart';
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
