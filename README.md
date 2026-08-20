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

Keys must be unique negative integers. Incoming frames have the form
`X,-1,-2,42`: negative numbers are replaced with their dictionary values and
positive numbers remain numeric. Invalid frames are displayed unchanged.
