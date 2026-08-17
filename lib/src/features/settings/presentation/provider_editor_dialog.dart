import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clarix/src/features/ai/ai.dart';
import '../../../core/workspace_surface_tokens.dart';

class ProviderEditorDialog extends ConsumerStatefulWidget {
  const ProviderEditorDialog({super.key, this.profile});

  final AiProviderProfile? profile;

  @override
  ConsumerState<ProviderEditorDialog> createState() =>
      ProviderEditorDialogState();
}

class ProviderEditorDialogState extends ConsumerState<ProviderEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _contextWindow;
  final TextEditingController _apiKey = TextEditingController();
  late bool _shareRetrievedPassages;
  bool _saving = false;
  bool _testing = false;
  String? _error;

  bool get _editing => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final AiProviderProfile? profile = widget.profile;
    _label = TextEditingController(text: profile?.label ?? '');
    _baseUrl = TextEditingController(text: profile?.baseUrl ?? '');
    _model = TextEditingController(text: profile?.modelId ?? '');
    _contextWindow = TextEditingController(
      text: '${profile?.contextWindowTokens ?? 256000}',
    );
    // Secrets are intentionally never read from storage into the UI.
    _shareRetrievedPassages = profile?.shareRetrievedPassages ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _contextWindow.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit provider' : 'Add provider'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _field(
                key: const Key('provider-label'),
                controller: _label,
                label: 'Label',
              ),
              _field(
                key: const Key('provider-base-url'),
                controller: _baseUrl,
                label: 'Base URL',
                keyboardType: TextInputType.url,
              ),
              _field(
                key: const Key('provider-model'),
                controller: _model,
                label: 'Model',
              ),
              _field(
                key: const Key('provider-context-window'),
                controller: _contextWindow,
                label: 'Context window (tokens)',
                keyboardType: TextInputType.number,
              ),
              _field(
                key: const Key('provider-api-key'),
                controller: _apiKey,
                label: 'API key',
                obscureText: true,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _shareRetrievedPassages,
                onChanged: (bool? value) =>
                    setState(() => _shareRetrievedPassages = value ?? false),
                title: const Text(
                  'Share retrieved passages with this provider',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: WorkspaceColors.warning),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving || _testing
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: _saving || _testing ? null : _testConnection,
          child: Text(_testing ? 'Testing…' : 'Test connection'),
        ),
        FilledButton(
          onPressed: _saving || _testing ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save provider'),
        ),
      ],
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: key,
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(labelText: label),
    ),
  );

  AiProviderProfile _buildProfile() => AiProviderProfile.create(
    id:
        widget.profile?.id ??
        'provider_${DateTime.now().microsecondsSinceEpoch}',
    label: _label.text,
    baseUrl: _baseUrl.text,
    modelId: _model.text,
    contextWindowTokens: int.tryParse(_contextWindow.text.trim()) ?? 0,
    shareRetrievedPassages: _shareRetrievedPassages,
  );

  Future<void> _testConnection() async {
    final AiProviderProfile profile;
    try {
      profile = _buildProfile();
    } catch (error) {
      setState(() => _error = _errorMessage(error));
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      await ref
          .read(aiNotifierProvider.notifier)
          .testProvider(profile, apiKey: _apiKey.text);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final AiProviderProfile profile;
    try {
      profile = _buildProfile();
    } catch (error) {
      setState(() => _error = _errorMessage(error));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(aiNotifierProvider.notifier);
      await notifier.saveProvider(profile, apiKey: _apiKey.text);
      await notifier.selectProvider(profile.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is ArgumentError && error.message != null) {
      return error.message.toString();
    }
    return error.toString();
  }
}
