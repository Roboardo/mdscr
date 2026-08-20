# Signal Chat

A Flutter mobile chat client for WebSocket-based signal languages. Incoming
WebSocket frames are displayed verbatim so each user can interpret them with
their own signal dictionary.

## Run

Install Flutter, then run:

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

Set the server address from the options screen. The default is the public
`wss://echo.websocket.events` echo service, which is useful for testing:
messages sent from the composer return as incoming frames.
