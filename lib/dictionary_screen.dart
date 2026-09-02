import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';
import 'signal_dictionary.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({
    required this.settings,
    required this.settingsRepository,
    super.key,
  });

  final AppSettings settings;
  final SettingsRepository settingsRepository;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  late AppSettings _settings;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';

  SignalDictionary get _dictionary => _settings.dictionary;

  List<MapEntry<int, String>> get _entries {
    final entries = _dictionary.entries.entries.toList()
      ..sort((first, second) => second.key.compareTo(first.key));
    final query = _searchQuery.trim().toUpperCase();
    return query.isEmpty
        ? entries
        : entries.where((entry) => entry.value.contains(query)).toList();
  }

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.pop(context, _settings);
  }

  Future<void> _saveDictionary(SignalDictionary dictionary) async {
    final settings = _settings.copyWith(dictionary: dictionary);
    setState(() => _settings = settings);
    await widget.settingsRepository.save(settings);
  }

  Future<void> _addEntry() async {
    await _editEntry();
  }

  void _startSearch() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocusNode.requestFocus(),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Future<void> _editEntry([int? signal]) async {
    final isNewEntry = signal == null;
    final defaultSignal = _dictionary.entries.keys.isEmpty
        ? -1
        : _dictionary.entries.keys.reduce((a, b) => a < b ? a : b) - 1;
    final entrySignal = signal ?? defaultSignal;
    final existingDescription = _dictionary.descriptions[entrySignal];
    final signalController = TextEditingController(text: entrySignal.toString());
    final valueController = TextEditingController(
      text: _dictionary.entries[entrySignal] ?? '',
    );
    final descriptionController = TextEditingController(
      text: existingDescription?.desc ?? _dictionary.entries[entrySignal] ?? '',
    );
    final update = await showDialog<_DictionaryEntryUpdate>(
      context: context,
      builder: (context) {
        var formatMode = existingDescription?.formatMode ??
            _dictionary.beforeUserDefaultMode;
        var formatModeAfter = existingDescription?.formatModeAfter ??
            _dictionary.afterUserDefaultMode;
        var breakOnDouble = existingDescription?.breakOnDouble ?? false;
        String? signalError;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              isNewEntry ? 'ADD ENTRY' : 'EDIT $entrySignal',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isNewEntry) ...[
                    TextField(
                      controller: signalController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'NUMBER',
                        errorText: signalError,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: valueController,
                    autofocus: !isNewEntry,
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
                    onChanged: (value) => setDialogState(
                      () => breakOnDouble = value ?? false,
                    ),
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
                onPressed: () {
                  final updatedSignal = int.tryParse(signalController.text);
                  if (updatedSignal == null || updatedSignal >= 0) {
                    setDialogState(
                      () => signalError = 'ENTER A NEGATIVE NUMBER',
                    );
                    return;
                  }
                  if (isNewEntry && _dictionary.entries.containsKey(updatedSignal)) {
                    setDialogState(
                      () => signalError = 'NUMBER ALREADY EXISTS',
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _DictionaryEntryUpdate(
                      signal: updatedSignal,
                      value: valueController.text,
                      description: descriptionController.text,
                      formatMode: formatMode,
                      formatModeAfter: formatModeAfter,
                      breakOnDouble: breakOnDouble,
                    ),
                  );
                },
                child: const Text('SAVE'),
              ),
            ],
          ),
        );
      },
    );
    signalController.dispose();
    valueController.dispose();
    descriptionController.dispose();

    if (update == null || update.value.trim().isEmpty || !mounted) {
      return;
    }
    await _saveDictionary(
      _dictionary.withEntry(
        update.signal,
        update.value.trim(),
        description: update.description.trim(),
        formatMode: update.formatMode,
        formatModeAfter: update.formatModeAfter,
        breakOnDouble: update.breakOnDouble,
      ),
    );
  }

  Future<void> _deleteEntry(int signal) async {
    await _saveDictionary(_dictionary.withoutEntry(signal));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return WillPopScope(
      onWillPop: () async {
        _close();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DICTIONARY'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'BACK',
            onPressed: _close,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'SEARCH WORDS',
              onPressed: _startSearch,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'ADD WORD',
              onPressed: () => unawaited(_addEntry()),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'SEARCH WORDS',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'CLEAR SEARCH',
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'NO DICTIONARY WORDS YET.'
                            : 'NO MATCHING WORDS.',
                      ),
                    )
                  : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  8 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: entries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Row(
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          entry.key.toString(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'EDIT WORD',
                        onPressed: () => unawaited(_editEntry(entry.key)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'DELETE WORD',
                        onPressed: () => unawaited(_deleteEntry(entry.key)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DictionaryEntryUpdate {
  const _DictionaryEntryUpdate({
    required this.signal,
    required this.value,
    required this.description,
    required this.formatMode,
    required this.formatModeAfter,
    required this.breakOnDouble,
  });

  final int signal;
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