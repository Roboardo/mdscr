import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'conversation_log.dart';
import 'graphic_message.dart';
import 'music_message.dart';
import 'settings.dart';
import 'signal_dictionary.dart';

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({
    required this.settings,
    required this.settingsRepository,
    required this.conversationLogRepository,
    super.key,
  });

  final AppSettings settings;
  final SettingsRepository settingsRepository;
  final ConversationLogRepository conversationLogRepository;

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _callSignController;
  late AppSettings _settings;
  late SignalDictionary _dictionary;
  late AppTheme _theme;
  late int _backgroundConnectionGraceSeconds;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _urlController = TextEditingController(text: _settings.webSocketUrl);
    _callSignController = TextEditingController(
      text: _settings.preferredCallSign == null
          ? ''
          : decimalCallSignToOctal(_settings.preferredCallSign!),
    );
    _dictionary = _settings.dictionary;
    _theme = _settings.theme;
    _backgroundConnectionGraceSeconds =
        _settings.backgroundConnectionGraceSeconds;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _callSignController.dispose();
    super.dispose();
  }

  Future<void> _persist(AppSettings settings) async {
    await widget.settingsRepository.save(settings);
    if (mounted) {
      setState(() => _settings = settings);
    }
  }

  Future<void> _saveAddress(String value) async {
    if (validateWebSocketUrl(value) != null) {
      return;
    }

    await _persist(_settings.copyWith(
      webSocketUrl: normalizeWebSocketUrl(value),
    ));
  }

  Future<void> _resetAddress() async {
    _urlController.text = defaultWebSocketUrl;
    await _saveAddress(defaultWebSocketUrl);
  }

  Future<void> _saveTheme(AppTheme theme) async {
    setState(() => _theme = theme);
    await _persist(_settings.copyWith(theme: theme));
  }

  Future<void> _saveCallSign(String value) async {
    if (validateCallSign(value) != null) {
      return;
    }
    final normalizedValue = value.trim();
    await _persist(
      normalizedValue.isEmpty
          ? _settings.copyWith(clearPreferredCallSign: true)
          : _settings.copyWith(
              preferredCallSign: octalCallSignToDecimal(normalizedValue),
            ),
    );
  }

  Future<void> _saveBackgroundConnectionGraceSeconds(int value) async {
    setState(() => _backgroundConnectionGraceSeconds = value);
    await _persist(
      _settings.copyWith(backgroundConnectionGraceSeconds: value),
    );
  }

  void _close() {
    Navigator.pop(context, _settings);
  }

  Future<void> _saveDictionary(SignalDictionary dictionary) async {
    setState(() => _dictionary = dictionary);
    await _persist(_settings.copyWith(
      dictionary: dictionary,
    ));
  }

  Future<void> _exportDictionary() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'EXPORT DICTIONARY',
      fileName: 'DICTIONARY-1.save',
      bytes: Uint8List.fromList(utf8.encode(_dictionary.toJsonString())),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path == null
              ? 'DICTIONARY EXPORT CANCELLED.'
              : 'DICTIONARY EXPORTED.',
        ),
      ),
    );
  }

  Future<void> _openConversationLog() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConversationLogScreen(
          repository: widget.conversationLogRepository,
          dictionary: _dictionary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _close();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('OPTIONS'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'CLOSE',
            onPressed: _close,
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SIGNAL SERVER',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'CHOOSE THE SIGNAL SERVER AND IMPORT YOUR PERSONAL DICTIONARY.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _urlController,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) => unawaited(_saveAddress(value)),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'WEBSOCKET ADDRESS',
                    hintText: 'wss://example.org/signals',
                    prefixIcon: const Icon(Icons.link),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.restart_alt),
                      tooltip: 'RESTORE DEFAULT ADDRESS',
                      onPressed: _settings.webSocketUrl == defaultWebSocketUrl
                          ? null
                          : _resetAddress,
                    ),
                  ),
                  validator: validateWebSocketUrl,
                ),
                const SizedBox(height: 16),
                const Text(
                  'USE WS:// ONLY FOR LOCAL OR TRUSTED DEVELOPMENT SERVERS. '
                  'USE WSS:// FOR PUBLIC SERVERS.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _callSignController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (value) => unawaited(_saveCallSign(value)),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'PREFERRED CALLSIGN',
                    hintText: 'RANDOM (1-4094)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: validateCallSign,
                ),
                const SizedBox(height: 32),
                Text(
                  'APPEARANCE',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<AppTheme>(
                  value: _theme,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'THEME',
                    prefixIcon: Icon(Icons.terminal),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AppTheme.terminalDark,
                      child: Text('TERMINAL DARK'),
                    ),
                    DropdownMenuItem(
                      value: AppTheme.terminalLight,
                      child: Text('TERMINAL LIGHT'),
                    ),
                  ],
                  onChanged: (theme) {
                    if (theme != null) {
                      unawaited(_saveTheme(theme));
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'BACKGROUND CONNECTION',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _backgroundConnectionGraceSeconds,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'KEEP ALIVE AFTER BACKGROUNDING',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('OFF')),
                    DropdownMenuItem(
                      value: permanentBackgroundConnection,
                      child: Text('PERMANENT'),
                    ),
                    DropdownMenuItem(value: 60, child: Text('1 MINUTE')),
                    DropdownMenuItem(value: 120, child: Text('2 MINUTES')),
                    DropdownMenuItem(value: 300, child: Text('5 MINUTES')),
                    DropdownMenuItem(value: 600, child: Text('10 MINUTES')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_saveBackgroundConnectionGraceSeconds(value));
                    }
                  },
                ),
                Text(
                  'DICTIONARY',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_dictionary.entries.length} IMPORTED WORD${_dictionary.entries.length == 1 ? '' : 'S'}',
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _importDictionary,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('IMPORT DICTIONARY FILE'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _exportDictionary,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('EXPORT DICTIONARY FILE'),
                ),
                const SizedBox(height: 32),
                Text(
                  'CONVERSATION LOG',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openConversationLog,
                  icon: const Icon(Icons.history),
                  label: const Text('VIEW TRANSLATED LOG'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importDictionary() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) {
      return;
    }

    try {
      final dictionary = SignalDictionary.fromJsonString(
        utf8.decode(result.files.single.bytes!),
      );
      if (mounted) {
        await _saveDictionary(dictionary);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('IMPORTED ${dictionary.entries.length} WORDS.')),
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('COULD NOT IMPORT DICTIONARY: ${error.message}')),
        );
      }
    }
  }
}

class ConversationLogScreen extends StatefulWidget {
  const ConversationLogScreen({
    required this.repository,
    required this.dictionary,
    super.key,
  });

  final ConversationLogRepository repository;
  final SignalDictionary dictionary;

  @override
  State<ConversationLogScreen> createState() => _ConversationLogScreenState();
}

class _ConversationLogScreenState extends State<ConversationLogScreen> {
  List<ConversationLogEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await widget.repository.load();
    if (mounted) {
      setState(() => _entries = entries);
    }
  }

  Future<void> _clearLog() async {
    await widget.repository.clear();
    if (mounted) {
      setState(() => _entries = const []);
    }
  }

  Future<void> _exportLog() async {
    final entries = await widget.repository.load();
    final text = entries
        .map(
          (entry) => '${_timestamp(entry.receivedAt)} | '
              '${decimalCallSignToOctal(entry.callSign)} | ${entry.sequence}\n'
              '${conversationLogText(entry, widget.dictionary)}',
        )
        .join('\n\n');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'EXPORT CONVERSATION LOG',
      fileName: 'CONVERSATION-LOG.txt',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path == null
              ? 'CONVERSATION LOG EXPORT CANCELLED.'
              : 'CONVERSATION LOG EXPORTED.',
        ),
      ),
    );
  }

  Future<void> _showMessageActions(ConversationLogEntry entry) async {
    final selection = await showModalBottomSheet<_LogCopyAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('COPY TEXT'),
              onTap: () => Navigator.pop(context, _LogCopyAction.text),
            ),
            ListTile(
              leading: const Icon(Icons.data_object_outlined),
              title: const Text('COPY RAW DATA'),
              onTap: () => Navigator.pop(context, _LogCopyAction.rawData),
            ),
          ],
        ),
      ),
    );
    if (selection == null) {
      return;
    }
    final text = selection == _LogCopyAction.text
        ? conversationLogText(entry, widget.dictionary)
        : rawConversationLogData(entry);
    await Clipboard.setData(ClipboardData(text: text));
  }

  String _timestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONVERSATION LOG'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'EXPORT LOG',
            onPressed: _exportLog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'CLEAR LOG',
            onPressed: _clearLog,
          ),
        ],
      ),
      body: switch (_entries) {
        null => const Center(child: CircularProgressIndicator()),
        [] => const Center(child: Text('NO CONVERSATION LOG YET.')),
        final entries => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              final spheres = entry.signals == null
                  ? null
                  : parseGraphicSpheres(entry.signals!);
              final notes = entry.signals == null
                  ? null
                  : parseMusicNotes(entry.signals!);
              return ListTile(
                onLongPress: () => _showMessageActions(entry),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (spheres != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GraphicMessage(
                          spheres: spheres,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GraphicViewerScreen(
                                  spheres: spheres,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (notes != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MusicMessage(notes: notes),
                      ),
                    Text(conversationLogText(entry, widget.dictionary)),
                  ],
                ),
                subtitle: Text(
                  '${_timestamp(entry.receivedAt)} | '
                  '${decimalCallSignToOctal(entry.callSign)} | ${entry.sequence}',
                ),
              );
            },
          ),
      },
    );
  }
}

enum _LogCopyAction { text, rawData }
