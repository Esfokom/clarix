import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../application/workspace_providers.dart';
import '../../domain/ai_provider.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

class ProviderSettingsSheet extends ConsumerStatefulWidget {
  const ProviderSettingsSheet({required this.state, super.key});
  final WorkspaceFeatureState state;

  @override
  ConsumerState<ProviderSettingsSheet> createState() =>
      _ProviderSettingsSheetState();
}

class _ProviderSettingsSheetState extends ConsumerState<ProviderSettingsSheet> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final TextEditingController _model = TextEditingController(text: 'gpt-5');
  final TextEditingController _key = TextEditingController();
  bool _sharePassages = true;
  String? _editingId;
  bool _testing = false;
  String? _testResult;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: WorkspaceColors.panel,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'AI providers',
                    style: TextStyle(
                      color: WorkspaceColors.textStrong,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .toggleProviderSettings(false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (final AiProviderProfile profile
                      in widget.state.providerProfiles)
                    ListTile(
                      title: Text(
                        '${profile.label} · ${profile.modelId}',
                        style: const TextStyle(
                          color: WorkspaceColors.textStrong,
                        ),
                      ),
                      subtitle: Text(
                        profile.shareRetrievedPassages
                            ? 'Retrieved PDF passages may be shared'
                            : 'Only your prompt is sent remotely',
                        style: const TextStyle(
                          color: WorkspaceColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        onPressed: () => _confirmDelete(profile),
                      ),
                      onTap: () => _edit(profile),
                    ),
                  const Divider(),
                  const Text(
                    'Add provider',
                    style: TextStyle(
                      color: WorkspaceColors.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _field(_label, 'Label', 'provider-label'),
                  _field(_baseUrl, 'Base URL', 'provider-base-url'),
                  _field(_model, 'Model', 'provider-model'),
                  _field(
                    _key,
                    'API key (stored securely)',
                    'provider-api-key',
                    obscure: true,
                  ),
                  SwitchListTile.adaptive(
                    value: _sharePassages,
                    onChanged: (bool value) =>
                        setState(() => _sharePassages = value),
                    title: const Text(
                      'Share retrieved PDF passages',
                      style: TextStyle(
                        color: WorkspaceColors.textStrong,
                        fontSize: 12,
                      ),
                    ),
                    subtitle: const Text(
                      'Clarix sends at most four bounded passages, never the full PDF.',
                      style: TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: WorkspaceColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  if (_testResult != null)
                    Text(
                      _testResult!,
                      style: const TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  const SizedBox(height: 8),
                  ShadButton.outline(
                    onPressed: _testing ? null : _testCredentials,
                    child: Text(_testing ? 'Testing…' : 'Test credentials'),
                  ),
                  const SizedBox(height: 8),
                  ShadButton(
                    onPressed: _save,
                    child: Text(
                      _editingId == null ? 'Save provider' : 'Save changes',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ShadInput(
      key: Key(key),
      controller: controller,
      obscureText: obscure,
      placeholder: Text(label),
    ),
  );

  Future<void> _save() async {
    try {
      final profile = AiProviderProfile.create(
        id:
            _editingId ??
            _label.text.trim().toLowerCase().replaceAll(
              RegExp('[^a-z0-9]+'),
              '-',
            ),
        label: _label.text,
        baseUrl: _baseUrl.text,
        modelId: _model.text,
        shareRetrievedPassages: _sharePassages,
      );
      await ref
          .read(workspaceNotifierProvider.notifier)
          .saveProvider(profile, apiKey: _key.text);
      if (mounted) setState(() => _error = null);
    } on ArgumentError catch (error) {
      setState(
        () =>
            _error = error.message?.toString() ?? 'Check the provider details.',
      );
    }
  }

  void _edit(AiProviderProfile profile) {
    setState(() {
      _editingId = profile.id;
      _label.text = profile.label;
      _baseUrl.text = profile.baseUrl;
      _model.text = profile.modelId;
      _key.clear();
      _sharePassages = profile.shareRetrievedPassages;
      _error = null;
      _testResult = null;
    });
  }

  Future<void> _testCredentials() async {
    try {
      final profile = AiProviderProfile.create(
        id:
            _editingId ??
            _label.text.trim().toLowerCase().replaceAll(
              RegExp('[^a-z0-9]+'),
              '-',
            ),
        label: _label.text,
        baseUrl: _baseUrl.text,
        modelId: _model.text,
        shareRetrievedPassages: _sharePassages,
      );
      setState(() {
        _testing = true;
        _error = null;
        _testResult = null;
      });
      await ref
          .read(workspaceNotifierProvider.notifier)
          .testProvider(profile, apiKey: _key.text);
      if (mounted) setState(() => _testResult = 'Credentials accepted.');
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _confirmDelete(AiProviderProfile profile) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete provider?'),
        content: Text(
          'Remove ${profile.label} and its securely stored API key?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(workspaceNotifierProvider.notifier)
          .deleteProvider(profile.id);
    }
  }
}
