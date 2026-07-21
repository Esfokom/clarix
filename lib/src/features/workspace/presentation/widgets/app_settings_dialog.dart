import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/workspace_providers.dart';
import '../../domain/ai_provider.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

Future<void> showAppSettingsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AppSettingsDialog(),
);

class AppSettingsDialog extends ConsumerWidget {
  const AppSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WorkspaceFeatureState? state = ref
        .watch(workspaceNotifierProvider)
        .value;
    return Dialog(
      backgroundColor: WorkspaceColors.panel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: state == null
              ? const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text(
                            'App settings',
                            style: TextStyle(
                              color: WorkspaceColors.textStrong,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close settings',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'AI providers',
                      style: TextStyle(
                        color: WorkspaceColors.textStrong,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Configure compatible remote AI providers for Clarix.',
                      style: TextStyle(color: WorkspaceColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    if (state.providerProfiles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(
                            'No providers configured',
                            style: TextStyle(color: WorkspaceColors.textMuted),
                          ),
                        ),
                      )
                    else
                      ...state.providerProfiles.map(
                        (AiProviderProfile profile) => _ProviderTile(
                          profile: profile,
                          isDefault:
                              profile.id == state.aiState.selectedProviderId,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _openEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add provider'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    AiProviderProfile? profile,
  }) => showDialog<void>(
    context: context,
    builder: (_) => _ProviderEditorDialog(profile: profile),
  );
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.profile, required this.isDefault});

  final AiProviderProfile profile;
  final bool isDefault;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: WorkspaceColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        profile.label,
                        style: const TextStyle(
                          color: WorkspaceColors.textStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isDefault) ...<Widget>[
                      const SizedBox(width: 8),
                      const Chip(label: Text('Default')),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${profile.baseUrl} · ${profile.modelId}',
                  style: const TextStyle(color: WorkspaceColors.textMuted),
                ),
              ],
            ),
          ),
          if (!isDefault)
            IconButton(
              tooltip: 'Make ${profile.label} default',
              onPressed: () => ref
                  .read(workspaceNotifierProvider.notifier)
                  .selectProvider(profile.id),
              icon: const Icon(Icons.check_circle_outline),
            ),
          IconButton(
            tooltip: 'Edit ${profile.label}',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ProviderEditorDialog(profile: profile),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete ${profile.label}',
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete provider?'),
        content: Text('Delete ${profile.label} and its stored API key?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete provider'),
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

class _ProviderEditorDialog extends ConsumerStatefulWidget {
  const _ProviderEditorDialog({this.profile});

  final AiProviderProfile? profile;

  @override
  ConsumerState<_ProviderEditorDialog> createState() =>
      _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends ConsumerState<_ProviderEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
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
    // Secrets are intentionally never read from storage into the UI.
    _shareRetrievedPassages = profile?.shareRetrievedPassages ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _model.dispose();
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
          .read(workspaceNotifierProvider.notifier)
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
      final notifier = ref.read(workspaceNotifierProvider.notifier);
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
