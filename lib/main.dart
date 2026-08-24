import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'conversation_log.dart';
import 'dictionary_screen.dart';
import 'graphic_message.dart';
import 'music_message.dart';
import 'options_screen.dart';
import 'settings.dart';
import 'signal_dictionary.dart';

void main() {
  runApp(const SignalChatApp());
}

ThemeData terminalTheme(AppTheme theme) {
  final isDark = theme == AppTheme.terminalDark;
  final colorScheme = ColorScheme.fromSeed(
    brightness: isDark ? Brightness.dark : Brightness.light,
    seedColor: const Color(0xff39ff14),
    surface: isDark ? const Color(0xff07110a) : const Color(0xffeef8e9),
    onSurface: isDark ? const Color(0xffc8f7c5) : const Color(0xff102515),
  );
  final baseTheme = ThemeData(
    brightness: colorScheme.brightness,
    colorScheme: colorScheme,
    fontFamily: 'monospace',
    useMaterial3: true,
  );
  return baseTheme.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor:
          isDark ? const Color(0xff0c1d10) : const Color(0xffdcefd5),
      foregroundColor: colorScheme.onSurface,
      centerTitle: false,
      titleTextStyle: baseTheme.textTheme.titleLarge?.copyWith(
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xff0c1d10) : const Color(0xffe5f2df),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xff0c1d10) : const Color(0xfff6fff2),
    ),
  );
}

class SignalChatApp extends StatelessWidget {
  const SignalChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDSCR',
      debugShowCheckedModeBanner: false,
      theme: terminalTheme(AppTheme.terminalDark),
      home: const ChatScreen(),
    );
  }
}

enum ConnectionStatus { connecting, connected, disconnected, error }

Color callSignColor(int callSign) {
  return HSLColor.fromAHSL(1, (137.5 * callSign) % 360, 1, 0.7).toColor();
}

class ChatMessage {
  const ChatMessage({
    required this.relayMessage,
    required this.receivedAt,
  });

  final RelayMessage relayMessage;
  final DateTime receivedAt;
}

String notificationBodyForRelayMessage(
  RelayMessage message,
  SignalDictionary dictionary,
) {
  if (isEncryptedRelayMessage(message)) {
    return 'ENCRYPTED SIGNAL MESSAGE';
  }
  final body = dictionary.formatSignals(visibleSignalsForRelayMessage(message));
  return String.fromCharCodes(body.runes.take(160));
}

TextEditingValue insertTextAtSelection(TextEditingValue value, String text) {
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  final updatedText = value.text.replaceRange(start, end, text);
  return value.copyWith(
    text: updatedText,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
  with TickerProviderStateMixin, WidgetsBindingObserver {
  final _settingsRepository = SharedPreferencesSettingsRepository();
  final _conversationLogRepository = SharedPreferencesConversationLogRepository();
  final _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<ChatMessage> _defaultMessages = [];
  final Map<int, List<ChatMessage>> _encryptedMessages = {};
  final Set<int> _encryptionKeys = {};
  final Set<String> _receivedMessageIds = {};
  final Set<int?> _unreadMessageKeys = {};
  static const _backgroundConnectionChannel = MethodChannel(
    'com.example.mdscr/background_connection',
  );

  AppSettings? _settings;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  late TabController _tabController;
  ConnectionStatus _connectionStatus = ConnectionStatus.connecting;
  String? _connectionDetail;
  int? _callSign;
  List<int> _activeCallSigns = const [];
  bool _isAppInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_onTabChanged);
    _messageController.addListener(_onComposerChanged);
    _loadSettingsAndConnect();
    unawaited(_requestNotificationPermission());
  }

  List<int> get _encryptionTabKeys {
    final keys = _encryptionKeys
        .where((key) => key != signalEncryptionSkeleton)
        .toList()
      ..sort();
    if (_encryptionKeys.contains(signalEncryptionSkeleton)) {
      keys.add(signalEncryptionSkeleton);
    }
    return keys;
  }

  int? get _selectedEncryptionKey {
    final tabIndex = _tabController.index;
    if (tabIndex == 0) {
      return null;
    }
    return _encryptionTabKeys[tabIndex - 1];
  }

  void _rebuildTabController({int? selectedEncryptionKey}) {
    final tabKeys = _encryptionTabKeys;
    final selectedIndex = selectedEncryptionKey == null
        ? 0
        : tabKeys.indexOf(selectedEncryptionKey) + 1;
    final previousController = _tabController;
    _tabController = TabController(
      length: tabKeys.length + 1,
      vsync: this,
      initialIndex: selectedIndex < 1 ? 0 : selectedIndex,
    );
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  void _onComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _markSelectedTabRead();
    }
  }

  void _markSelectedTabRead() {
    final encryptionKey = _selectedEncryptionKey;
    if (_unreadMessageKeys.remove(encryptionKey) && mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = _settings;
    if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      unawaited(_stopBackgroundConnection());
    } else if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        settings != null &&
        settings.backgroundConnectionGraceSeconds != 0 &&
        _connectionStatus == ConnectionStatus.connected) {
      _isAppInForeground = false;
      unawaited(
        _startBackgroundConnection(settings.backgroundConnectionGraceSeconds),
      );
    } else {
      _isAppInForeground = false;
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await _backgroundConnectionChannel.invokeMethod<void>(
        'requestNotificationPermission',
      );
    } on PlatformException {
      // Notification permissions are currently implemented for Android.
    } on MissingPluginException {
      // Other platforms use their normal notification permissions.
    }
  }

  Future<void> _startBackgroundConnection(int graceSeconds) async {
    try {
      await _backgroundConnectionChannel.invokeMethod<void>(
        'start',
        {'graceSeconds': graceSeconds},
      );
    } on PlatformException {
      // Background connection support is currently implemented for Android.
    } on MissingPluginException {
      // Other platforms continue with their normal lifecycle behavior.
    }
  }

  Future<void> _stopBackgroundConnection() async {
    try {
      await _backgroundConnectionChannel.invokeMethod<void>('stop');
    } on PlatformException {
      // The service may already have stopped after its grace period.
    } on MissingPluginException {
      // Other platforms continue with their normal lifecycle behavior.
    }
  }

  Future<void> _loadSettingsAndConnect() async {
    final settings = await _settingsRepository.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _encryptionKeys
        ..clear()
        ..addAll(settings.activeEncryptionKeys);
      _rebuildTabController();
    });
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
        final packet = frame.toString();
        final relayMessage = parseRelayMessage(packet);
        final assignedCallSign = parseCallSignAssignment(packet);
        final activeCallSigns = parseActiveCallSigns(packet);
        if (mounted && identical(channel, _channel)) {
          setState(() {
            if (relayMessage != null) {
              final messageId = relayMessageId(relayMessage);
              if (_receivedMessageIds.add(messageId)) {
                final message = ChatMessage(
                  relayMessage: relayMessage,
                  receivedAt: DateTime.now(),
                );
                _messages.add(message);
                unawaited(
                  _conversationLogRepository.add(
                    relayMessage,
                    message.receivedAt,
                    settings.dictionary,
                  ),
                );
                final encryptionKey = encryptionKeyForRelayMessage(relayMessage);
                if (encryptionKey == null) {
                  _defaultMessages.add(message);
                } else {
                  _encryptedMessages
                      .putIfAbsent(encryptionKey, () => [])
                      .add(message);
                }
                if (_tabController.length > 1 &&
                    encryptionKey != _selectedEncryptionKey) {
                  _unreadMessageKeys.add(encryptionKey);
                }
                if (!_isAppInForeground) {
                  unawaited(_showIncomingMessageNotification(message));
                }
              }
            }
            if (assignedCallSign != null) {
              _callSign = assignedCallSign;
            }
            if (activeCallSigns != null) {
              _activeCallSigns = activeCallSigns;
            }
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
        setState(() {
          _connectionStatus = ConnectionStatus.connected;
          _callSign = null;
        });
        final requestedCallSign =
          settings.preferredCallSign ?? Random().nextInt(4094) + 1;
        channel.sink.add('S,$requestedCallSign');
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

  Future<void> _showIncomingMessageNotification(ChatMessage message) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    try {
      await _backgroundConnectionChannel.invokeMethod<void>(
        'showIncomingMessageNotification',
        {
          'callSign': decimalCallSignToOctal(message.relayMessage.callSign),
          'message': notificationBodyForRelayMessage(
            message.relayMessage,
            settings.dictionary,
          ),
        },
      );
    } on PlatformException {
      // Notifications are currently implemented for Android.
    } on MissingPluginException {
      // Other platforms do not yet provide a notification implementation.
    }
  }

  Future<void> _editDictionaryEntry(int signal) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    final existingDescription = settings.dictionary.descriptions[signal];
    final valueController = TextEditingController(
      text: settings.dictionary.entries[signal] ?? '',
    );
    final descriptionController = TextEditingController(
      text: existingDescription?.desc ?? settings.dictionary.entries[signal] ?? '',
    );
    final entry = await showDialog<_DictionaryEntryUpdate>(
      context: context,
      builder: (context) {
        var formatMode = existingDescription?.formatMode ??
            settings.dictionary.beforeUserDefaultMode;
        var formatModeAfter = existingDescription?.formatModeAfter ??
            settings.dictionary.afterUserDefaultMode;
        var breakOnDouble = existingDescription?.breakOnDouble ?? false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              settings.dictionary.entries.containsKey(signal)
                  ? 'EDIT $signal'
                  : 'ADD $signal',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: valueController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) => newValue.copyWith(
                          text: newValue.text.toUpperCase(),
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'DICTIONARY VALUE',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'TRANSLATOR NOTES',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SignalFormatMode>(
                    value: formatMode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'BEFORE',
                    ),
                    items: _formatModeItems,
                    onChanged: (value) =>
                        setDialogState(() => formatMode = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SignalFormatMode>(
                    value: formatModeAfter,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'AFTER',
                    ),
                    items: _formatModeItems,
                    onChanged: (value) =>
                        setDialogState(() => formatModeAfter = value!),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: breakOnDouble,
                    onChanged: (value) =>
                        setDialogState(() => breakOnDouble = value ?? false),
                    title: const Text('BREAK ON DOUBLE'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _DictionaryEntryUpdate(
                    value: valueController.text,
                    description: descriptionController.text,
                    formatMode: formatMode,
                    formatModeAfter: formatModeAfter,
                    breakOnDouble: breakOnDouble,
                  ),
                ),
                child: const Text('SAVE'),
              ),
            ],
          ),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      valueController.dispose();
      descriptionController.dispose();
    });

    if (entry == null || entry.value.trim().isEmpty || !mounted) {
      return;
    }
    final updatedSettings = settings.copyWith(
      dictionary: settings.dictionary.withEntry(
        signal,
        entry.value.trim(),
        description: entry.description.trim(),
        formatMode: entry.formatMode,
        formatModeAfter: entry.formatModeAfter,
        breakOnDouble: entry.breakOnDouble,
      ),
    );
    await _settingsRepository.save(updatedSettings);
    if (mounted) {
      setState(() => _settings = updatedSettings);
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

  Future<void> _sendMessage() async {
    final settings = _settings;
    final message = _messageController.text;
    if (settings == null ||
        message.trim().isEmpty ||
        _connectionStatus != ConnectionStatus.connected) {
      return;
    }
    final signals = settings.dictionary.encodeMessage(message);
    if (signals == null || signals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EVERY WORD MUST EXIST IN YOUR DICTIONARY.'),
        ),
      );
      return;
    }
    if (signals.first == signalEncryptionEnable ||
        signals.first == signalEncryptionDisable) {
      if (signals.length != 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('EXACTLY TWO SIGNALS ARE REQUIRED.')),
        );
        return;
      }
      final encryptionKey = signals[1];
      final selectedEncryptionKey = _selectedEncryptionKey;
      late AppSettings updatedSettings;
      setState(() {
        if (signals.first == signalEncryptionEnable) {
          _encryptionKeys.add(encryptionKey);
          _rebuildTabController(selectedEncryptionKey: encryptionKey);
        } else {
          _encryptionKeys.remove(encryptionKey);
          _rebuildTabController(
            selectedEncryptionKey: selectedEncryptionKey == encryptionKey
                ? null
                : selectedEncryptionKey,
          );
        }
        updatedSettings = settings.copyWith(
          activeEncryptionKeys: _encryptionKeys.toList(),
        );
        _settings = updatedSettings;
      });
      await _settingsRepository.save(updatedSettings);
      _messageController.clear();
      return;
    }
    final encryptionKey = _selectedEncryptionKey;
    final outgoingSignals = encryptionKey == null ||
            encryptionKey == signalEncryptionSkeleton
        ? signals
        : [signalEncryption, encryptionKey, ...signals];
    _channel!.sink.add('M,${outgoingSignals.join(',')}');
    _messageController.clear();
  }

  void _insertSuggestion(MapEntry<int, String> suggestion) {
    final text = _messageController.text;
    final tokenStart = text.lastIndexOf(RegExp(r'\s')) + 1;
    final updatedText = '${text.substring(0, tokenStart)}${suggestion.value} ';
    _messageController.value = TextEditingValue(
      text: updatedText,
      selection: TextSelection.collapsed(offset: updatedText.length),
    );
  }

  void _insertMessageNumber(String number) {
    _messageController.value =
        insertTextAtSelection(_messageController.value, number);
  }

  List<ChatMessage> _messagesForTab(int? encryptionKey) {
    if (encryptionKey == signalEncryptionSkeleton) {
      return _messages;
    }
    if (encryptionKey == null) {
      return _defaultMessages;
    }
    return _encryptedMessages[encryptionKey] ?? const [];
  }

  String _encryptionKeyLabel(int key, SignalDictionary? dictionary) {
    return dictionary?.entries[key] ?? key.toString();
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
          conversationLogRepository: _conversationLogRepository,
        ),
      ),
    );
    if (updatedSettings != null && mounted) {
      final addressChanged =
          updatedSettings.webSocketUrl != settings.webSocketUrl;
      setState(() => _settings = updatedSettings);
      if (addressChanged) {
        await _connect();
      }
    }
  }

  Future<void> _openDictionary() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    final updatedSettings = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => DictionaryScreen(
          settings: settings,
          settingsRepository: _settingsRepository,
        ),
      ),
    );
    if (updatedSettings != null && mounted) {
      setState(() => _settings = updatedSettings);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _messageController.removeListener(_onComposerChanged);
    _messageController.dispose();
    unawaited(_disconnect(updateStatus: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final query =
        _messageController.text.split(RegExp(r'\s')).last.toUpperCase();
    final suggestions = settings?.dictionary.matchingEntries(query) ?? const [];
    final encryptionTabKeys = _encryptionTabKeys;
    return Theme(
      data: terminalTheme(settings?.theme ?? AppTheme.terminalDark),
      child: Scaffold(
        appBar: AppBar(
          title: _ConnectionHeader(
            status: _connectionStatus,
            detail: _connectionDetail,
            callSign: _callSign,
            activeCallSigns: _activeCallSigns.length,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'RECONNECT',
              onPressed: settings == null ? null : _connect,
            ),
            IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: 'DICTIONARY',
              onPressed: settings == null ? null : _openDictionary,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'OPTIONS',
              onPressed: settings == null ? null : _openOptions,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_callSign != null)
              Material(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: [
                    _buildTab('DEFAULT', null),
                    for (final key in encryptionTabKeys)
                      _buildTab(
                        _encryptionKeyLabel(key, settings?.dictionary),
                        key,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildMessageList(
                    null,
                    dictionary: settings?.dictionary,
                  ),
                  for (final key in encryptionTabKeys)
                    _buildMessageList(
                      key,
                      dictionary: settings?.dictionary,
                      showEncryptionStatus: key == signalEncryptionSkeleton,
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (suggestions.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 4,
                                children: [
                                  for (final suggestion in suggestions.take(5))
                                    ActionChip(
                                      label: Text(suggestion.value),
                                      onPressed: _connectionStatus ==
                                              ConnectionStatus.connected
                                          ? () => _insertSuggestion(suggestion)
                                          : null,
                                    ),
                                ],
                              ),
                            ),
                          TextField(
                            controller: _messageController,
                            enabled:
                                _connectionStatus == ConnectionStatus.connected,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) => newValue.copyWith(
                                  text: newValue.text.toUpperCase(),
                                ),
                              ),
                            ],
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'SEND A MESSAGE',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      tooltip: 'SEND',
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
      ),
    );
  }

  _MessageList _buildMessageList(
    int? encryptionKey, {
    required SignalDictionary? dictionary,
    bool showEncryptionStatus = false,
  }) {
    final messages = _messagesForTab(encryptionKey);
    return _MessageList(
      key: ValueKey(encryptionKey),
      messages: messages,
      dictionary: dictionary,
      onEditSignal: _editDictionaryEntry,
      onInsertNumber: _insertMessageNumber,
      encryptionKeyLabel: (key) => _encryptionKeyLabel(key, dictionary),
      showEncryptionStatus: showEncryptionStatus,
    );
  }

  Tab _buildTab(String label, int? encryptionKey) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (_unreadMessageKeys.contains(encryptionKey))
            Container(
              key: ValueKey('unread-tab-$encryptionKey'),
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({
    super.key,
    required this.messages,
    required this.dictionary,
    required this.onEditSignal,
    required this.onInsertNumber,
    required this.encryptionKeyLabel,
    this.showEncryptionStatus = false,
  });

  final List<ChatMessage> messages;
  final SignalDictionary? dictionary;
  final ValueChanged<int> onEditSignal;
  final ValueChanged<String> onInsertNumber;
  final String Function(int key) encryptionKeyLabel;
  final bool showEncryptionStatus;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList>
  with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _collapseThreshold = 100;
  final _scrollController = ScrollController();
  final Set<String> _expandedMessageIds = {};
  late int _messageCount;
  bool _wasAtBottom = true;

  @override
  void initState() {
    super.initState();
    _messageCount = widget.messages.length;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateBottomPosition);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_updateBottomPosition);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  void _updateBottomPosition() {
    if (_scrollController.hasClients) {
      _wasAtBottom = _scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 1;
    }
  }

  @override
  void didChangeMetrics() {
    if (_wasAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasNewMessages = widget.messages.length > _messageCount;
    final isAtBottom = _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 1;
    _messageCount = widget.messages.length;
    if (hasNewMessages && isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.messages.isEmpty) {
      return const Center(child: Text('WAITING FOR SIGNALS...'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final chatMessage = widget.messages[index];
        final message = chatMessage.relayMessage;
        final encryptionKey = encryptionKeyForRelayMessage(message);
        final signals = visibleSignalsForRelayMessage(message);
        final messageId = relayMessageId(message);
        final isLongMessage = signals.length > _collapseThreshold;
        final isExpanded = _expandedMessageIds.contains(messageId);
        final displayedSignals = isLongMessage && !isExpanded
            ? signals.take(_collapseThreshold).toList()
            : signals;
        final graphicSpheres = parseGraphicSpheres(signals);
        final musicNotes = parseMusicNotes(signals);
        final encryptionStatus = encryptionKey == null
            ? 'UNENCRYPTED'
            : 'ENCRYPTED ${widget.encryptionKeyLabel(encryptionKey)}';
        return Column(
          key: ValueKey(messageId),
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (graphicSpheres != null) ...[
                GraphicMessage(
                  spheres: graphicSpheres,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            GraphicViewerScreen(spheres: graphicSpheres),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (musicNotes != null) ...[
                MusicMessage(notes: musicNotes),
                const SizedBox(height: 8),
              ],
              Text.rich(
                TextSpan(
                  children: [
                    for (var index = 0; index < displayedSignals.length; index++) ...[
                      if (index > 0)
                        TextSpan(
                          text: widget.dictionary?.separatorBeforeSignal(
                                displayedSignals,
                                index,
                              ) ??
                              ' ',
                        ),
                      WidgetSpan(
                        child: _SignalToken(
                          signal: displayedSignals[index],
                          value: displayedSignals[index] < 0
                              ? widget.dictionary?.displayTextForSignal(
                                  displayedSignals[index],
                                )
                              : null,
                          onTap: displayedSignals[index] < 0
                              ? () => widget.onEditSignal(displayedSignals[index])
                              : () => widget.onInsertNumber(
                                  displayedSignals[index].toString(),
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
                ],
              ),
              subtitle: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
              _MessageNumberButton(
                value: decimalCallSignToOctal(message.callSign),
                color: callSignColor(message.callSign),
                onTap: () => widget.onInsertNumber(
                  decimalCallSignToOctal(message.callSign),
                ),
              ),
              const Text(' | '),
              _MessageNumberButton(
                value: message.sequence.toString(),
                onTap: () => widget.onInsertNumber(message.sequence.toString()),
              ),
              if (widget.showEncryptionStatus)
                Text(' | $encryptionStatus'),
                ],
              ),
              trailing: isLongMessage
                  ? IconButton(
                      icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      tooltip: isExpanded
                          ? 'COLLAPSE MESSAGE'
                          : 'EXPAND MESSAGE',
                      onPressed: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedMessageIds.remove(messageId);
                          } else {
                            _expandedMessageIds.add(messageId);
                          }
                        });
                      },
                    )
                  : null,
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _SignalToken extends StatelessWidget {
  const _SignalToken({
    required this.signal,
    required this.value,
    required this.onTap,
  });

  final int signal;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        signal >= 0 ? signal.toString() : value ?? '@${signal}_UNDEF',
      ),
    );
  }
}

class _DictionaryEntryUpdate {
  const _DictionaryEntryUpdate({
    required this.value,
    required this.description,
    required this.formatMode,
    required this.formatModeAfter,
    required this.breakOnDouble,
  });

  final String value;
  final String description;
  final SignalFormatMode formatMode;
  final SignalFormatMode formatModeAfter;
  final bool breakOnDouble;
}

final _formatModeItems = [
  for (final mode in SignalFormatMode.values)
    DropdownMenuItem(
      value: mode,
      child: Text(switch (mode) {
        SignalFormatMode.none => 'NO SPACE',
        SignalFormatMode.space => 'ONE SPACE',
        SignalFormatMode.lineBreak => 'ONE LINE BREAK',
        SignalFormatMode.doubleLineBreak => 'TWO LINE BREAKS',
      }),
    ),
];

class _MessageNumberButton extends StatelessWidget {
  const _MessageNumberButton({
    required this.value,
    required this.onTap,
    this.color,
  });

  final String value;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        value,
        style: color == null ? null : TextStyle(color: color),
      ),
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({
    required this.status,
    required this.detail,
    required this.callSign,
    required this.activeCallSigns,
  });

  final ConnectionStatus status;
  final String? detail;
  final int? callSign;
  final int activeCallSigns;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ConnectionStatus.connecting => (Colors.orange, 'Connecting'),
      ConnectionStatus.connected => (Colors.green, 'Connected'),
      ConnectionStatus.disconnected => (Colors.grey, 'Disconnected'),
      ConnectionStatus.error => (Colors.red, 'Connection error'),
    };
    final displayedCallSign = callSign == null
        ? null
        : decimalCallSignToOctal(callSign!);

    return Row(
      children: [
        const Text('MDSCR'),
        const SizedBox(width: 8),
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            (detail == null
                    ? '$label${displayedCallSign == null ? '' : ' AS $displayedCallSign'} '
                        '($activeCallSigns ACTIVE)'
                    : '$label: $detail')
                .toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
