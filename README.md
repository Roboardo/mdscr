# MDSCR

A Flutter-based Android chat client for WebSocket signal languages. Incoming
WebSocket frames are displayed verbatim so each user can interpret them with
their own signal dictionary.

## Build an Android APK

The supported build path uses Docker, so a local Flutter or Android SDK
installation is not required. Install Docker Engine, ensure the Docker daemon
is running, then clone this repository and run:

```sh
git clone https://github.com/Roboardo/mdscr.git
cd mdscr
make apk
```

The APK is created at `build/app/outputs/flutter-apk/app-debug.apk`. The first
build pulls `ghcr.io/cirruslabs/flutter:stable`; later builds reuse
`.docker-cache/` for Dart, Gradle, and Android tool caches. To use a specific
Flutter image, override `FLUTTER_IMAGE`:

```sh
make apk FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.24.5
```

`make apk-release` produces `app-release.apk`, signed with a debug key for
local installation. Before distributing a release APK, configure your own
Android release-signing key in `android/app/build.gradle.kts`.

## Develop

Install Flutter and the Android SDK, then run `flutter pub get` followed by
`flutter run`. The versioned Gradle wrapper supports Android Studio and command
line Android builds without regenerating the platform project.

## Contributing

Please open an issue before starting substantial changes. Keep pull requests
focused, include tests when behavior changes, and verify Android builds with
`make apk`.

Set the server address from the options screen. The default is
`wss://dscr-relay.dixonary.co.uk`. The public DSCR website address
`wss://dscr.dixonary.co.uk` does not accept WebSocket upgrades and is
automatically migrated to the relay.

## Background notifications

When the app is backgrounded, incoming Android messages are collected in one
expandable notification while the configured background connection keep-alive
period is active. It alerts for the first message only. Choose **Permanent** to
keep the connection active until the app is opened again or the status
notification's **Stop background connection** action is selected. Android 13
and later will ask for notification permission when the app starts. Encrypted
messages are announced without including their contents.

## Dictionaries

Import a dictionary from Options. Files are read as UTF-8 JSON regardless of
their extension and must use this shape:

```json
{
  "wordDict": {
    "keys": [-1, -2],
    "values": ["first word", "second word"]
  }
}
```

Keys must be unique negative integers. Relay messages such as
`R,2058,83,-1,-2,42` are shown as chat messages from callsign `2058`; the
sequence is not displayed. Dictionary values replace negative signals. Unknown
signals are shown as `@-1_UNDEF`; tap any negative signal to add or edit its
dictionary value.

## License

MDSCR is released under the [MIT License](LICENSE).
