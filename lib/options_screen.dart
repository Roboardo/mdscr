import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'settings.dart';
import 'signal_dictionary.dart';

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({
    required this.settings,
    required this.settingsRepository,
    super.key,
  });

  final AppSettings settings;
  final SettingsRepository settingsRepository;

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late SignalDictionary _dictionary;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.settings.webSocketUrl);
    _dictionary = widget.settings.dictionary;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final settings = widget.settings.copyWith(
      webSocketUrl: _urlController.text.trim(),
      dictionary: _dictionary,
    );
    await widget.settingsRepository.save(settings);
    if (mounted) {
      Navigator.pop(context, settings);
    }
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
        setState(() => _dictionary = dictionary);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${dictionary.entries.length} words.')),
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import dictionary: ${error.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Options')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Signal server',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose the signal server and import your personal dictionary.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _urlController,
                autocorrect: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'WebSocket address',
                  hintText: 'wss://example.org/signals',
                  prefixIcon: Icon(Icons.link),
                ),
                validator: validateWebSocketUrl,
              ),
              const SizedBox(height: 16),
              const Text(
                'Use ws:// only for local or trusted development servers. '
                'Use wss:// for public servers.',
              ),
              const SizedBox(height: 32),
              Text(
                'Dictionary',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${_dictionary.entries.length} imported word${_dictionary.entries.length == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _importDictionary,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import dictionary file'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Any file extension is accepted. Expected JSON: '
                '{"wordDict":{"keys":[-1],"values":["word"]}}',
              ),
              const Spacer(),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Saving...' : 'Save and reconnect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
