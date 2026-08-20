import 'package:flutter/material.dart';

import 'settings.dart';

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.settings.webSocketUrl);
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
    );
    await widget.settingsRepository.save(settings);
    if (mounted) {
      Navigator.pop(context, settings);
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
                'Incoming frames are shown exactly as the server sends them.',
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
