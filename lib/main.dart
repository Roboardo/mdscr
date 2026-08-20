import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'options_screen.dart';
import 'settings.dart';
import 'signal_dictionary.dart';

void main() {
  runApp(const SignalChatApp());
}

class SignalChatApp extends StatelessWidget {
  const SignalChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signal Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

enum ConnectionStatus { connecting, connected, disconnected, error }

class ChatMessage {
  const ChatMessage({
    required this.rawValue,
    required this.receivedAt,
  });

  final String rawValue;
  final DateTime receivedAt;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _settingsRepository = SharedPreferencesSettingsRepository();
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];

  AppSettings? _settings;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  ConnectionStatus _connectionStatus = ConnectionStatus.connecting;
  String? _connectionDetail;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndConnect();
  }

  Future<void> _loadSettingsAndConnect() async {
    final settings = await _settingsRepository.load();
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    await _disconnect(updateStatus: false);
    if (!mounted) {
      return;
    }

    setState(() {
      _connectionStatus = ConnectionStatus.connecting;
      _connectionDetail = null;
    });

    final channel = WebSocketChannel.connect(Uri.parse(settings.webSocketUrl));
    _channel = channel;
    _subscription = channel.stream.listen(
      (frame) {
        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(
              rawValue: frame.toString(),
              receivedAt: DateTime.now(),
            ));
          });
        }
      },
      onError: (Object error) {
        if (mounted && identical(channel, _channel)) {
          setState(() {
            _connectionStatus = ConnectionStatus.error;
            _connectionDetail = error.toString();
          });
        }
      },
      onDone: () {
        if (mounted && identical(channel, _channel)) {
          setState(() => _connectionStatus = ConnectionStatus.disconnected);
        }
      },
    );
    try {
      await channel.ready;
      if (mounted && identical(channel, _channel)) {
        setState(() => _connectionStatus = ConnectionStatus.connected);
      }
    } on WebSocketChannelException catch (error) {
      if (mounted && identical(channel, _channel)) {
        setState(() {
          _connectionStatus = ConnectionStatus.error;
          _connectionDetail = error.toString();
        });
      }
    }
  }

  Future<void> _disconnect({bool updateStatus = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (mounted && updateStatus) {
      setState(() => _connectionStatus = ConnectionStatus.disconnected);
    }
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty || _connectionStatus != ConnectionStatus.connected) {
      return;
    }
    _channel!.sink.add(message);
    _messageController.clear();
  }

  Future<void> _openOptions() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final updatedSettings = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => OptionsScreen(
          settings: settings,
          settingsRepository: _settingsRepository,
        ),
      ),
    );
    if (updatedSettings != null && mounted) {
      setState(() => _settings = updatedSettings);
      await _connect();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    unawaited(_disconnect(updateStatus: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signal Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect',
            onPressed: settings == null ? null : _connect,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Options',
            onPressed: settings == null ? null : _openOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionBanner(
            status: _connectionStatus,
            address: settings?.webSocketUrl,
            detail: _connectionDetail,
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('Waiting for signals...'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final time = TimeOfDay.fromDateTime(message.receivedAt);
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.waves)),
                        title: SelectableText(
                          translateSignalFrame(
                            message.rawValue,
                            settings?.dictionary ?? const SignalDictionary.empty(),
                          ),
                        ),
                        subtitle: Text('${time.format(context)}  ${message.rawValue}'),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: _connectionStatus == ConnectionStatus.connected,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Send a signal',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    tooltip: 'Send',
                    onPressed: _connectionStatus == ConnectionStatus.connected
                        ? _sendMessage
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.status,
    required this.address,
    required this.detail,
  });

  final ConnectionStatus status;
  final String? address;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ConnectionStatus.connecting => (Colors.orange, 'Connecting'),
      ConnectionStatus.connected => (Colors.green, 'Connected'),
      ConnectionStatus.disconnected => (Colors.grey, 'Disconnected'),
      ConnectionStatus.error => (Colors.red, 'Connection error'),
    };

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail == null ? '$label${address == null ? '' : ': $address'}' : '$label: $detail',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
