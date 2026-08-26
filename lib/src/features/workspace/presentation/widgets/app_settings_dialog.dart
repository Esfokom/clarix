import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../application/workspace_providers.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:clarix/src/features/settings/settings.dart';
import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import '../../../../core/reader_background_store.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

Future<void> showAppSettingsDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AppSettingsDialog(),
);

class AppSettingsDialog extends ConsumerStatefulWidget {
  const AppSettingsDialog({super.key});

  @override
  ConsumerState<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends ConsumerState<AppSettingsDialog> {
  int _tab = 2;

  @override
  Widget build(BuildContext context) {
    final WorkspaceFeatureState? state = ref
        .watch(workspaceNotifierProvider)
        .value;
    final AiFeatureState aiState =
        ref.watch(aiNotifierProvider).value ?? AiFeatureState.initial();
    return Dialog(
      backgroundColor: WorkspaceColors.panel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
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
                    const SizedBox(height: 4),
                    _SettingsTabs(
                      selected: _tab,
                      onSelected: (value) => setState(() => _tab = value),
                    ),
                    const Divider(height: 25, color: WorkspaceColors.border),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 8),
                        child: _tab == 0
                            ? _FontSettings(ref: ref)
                            : _tab == 1
                            ? _ThemeSettings(ref: ref)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const _SettingsHeading(
                                    title: 'AI providers',
                                    description:
                                        'Configure compatible remote AI providers for Clarix.',
                                  ),
                                  const SizedBox(height: 16),
                                  if (aiState.providerProfiles.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No providers configured',
                                          style: TextStyle(
                                            color: WorkspaceColors.textMuted,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    ...aiState.providerProfiles.map(
                                      (AiProviderProfile profile) =>
                                          _ProviderTile(
                                            profile: profile,
                                            isDefault:
                                                profile.id ==
                                                aiState.chat.selectedProviderId,
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
                                  const SizedBox(height: 24),
                                  const Text(
                                    'Storage',
                                    style: TextStyle(
                                      color: WorkspaceColors.textStrong,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Manage locally stored AI conversations.',
                                    style: TextStyle(
                                      color: WorkspaceColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    key: const Key('clear-document-cache'),
                                    onPressed: () => ref
                                        .read(
                                          workspaceNotifierProvider.notifier,
                                        )
                                        .clearDocumentCache(),
                                    icon: const Icon(Icons.cached_outlined),
                                    label: const Text('Clear document cache'),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    key: const Key('clear-all-conversations'),
                                    onPressed: () => _confirmClearConversations(
                                      context,
                                      ref,
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text(
                                      'Clear all conversations',
                                    ),
                                  ),
                                ],
                              ),
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
    builder: (_) => ProviderEditorDialog(profile: profile),
  );

  Future<void> _confirmClearConversations(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear all conversations?'),
        content: const Text(
          'This permanently removes saved AI conversations. Document cache, providers, and API keys are retained.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear conversations'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(aiNotifierProvider.notifier).clearAllConversations();
    }
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: <Widget>[
      _tab(0, Icons.text_fields_outlined, 'Font'),
      _tab(1, Icons.palette_outlined, 'Theme'),
      _tab(2, Icons.tune_outlined, 'Settings'),
    ],
  );

  Widget _tab(int index, IconData icon, String label) {
    final active = selected == index;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: active
            ? WorkspaceColors.textStrong
            : WorkspaceColors.textMuted,
        backgroundColor: active
            ? WorkspaceColors.panelRaised
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
      onPressed: () => onSelected(index),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _SettingsHeading extends StatelessWidget {
  const _SettingsHeading({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        style: const TextStyle(
          color: WorkspaceColors.textStrong,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        description,
        style: const TextStyle(color: WorkspaceColors.textMuted),
      ),
    ],
  );
}

class _FontSettings extends StatelessWidget {
  const _FontSettings({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final profile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SettingsHeading(
          title: 'Interface font',
          description: 'Choose the typeface used throughout Clarix.',
        ),
        const SizedBox(height: 18),
        ...ClarixFont.values.map(
          (font) => _FontOption(
            font: font,
            selected: profile.font == font,
            onTap: () => ref
                .read(clarixThemeProvider.notifier)
                .setProfile(profile.copyWith(font: font)),
          ),
        ),
      ],
    );
  }
}

class _FontOption extends StatelessWidget {
  const _FontOption({
    required this.font,
    required this.selected,
    required this.onTap,
  });
  final ClarixFont font;
  final bool selected;
  final VoidCallback onTap;

  String get _name => switch (font) {
    ClarixFont.sans => 'Sans',
    ClarixFont.serif => 'Serif',
    ClarixFont.mono => 'Mono',
  };
  String get _sample => switch (font) {
    ClarixFont.sans => 'Clear, versatile, and compact',
    ClarixFont.serif => 'Comfortable for longer reading',
    ClarixFont.mono => 'Precise and code-friendly',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? WorkspaceColors.accentSoft
              : WorkspaceColors.panelRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? WorkspaceColors.accentBorder
                : WorkspaceColors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? WorkspaceColors.textStrong
                  : WorkspaceColors.textFaint,
              size: 19,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _name,
                    style: TextStyle(
                      color: WorkspaceColors.textStrong,
                      fontSize: 15,
                      fontFamily: font == ClarixFont.serif
                          ? 'serif'
                          : font == ClarixFont.mono
                          ? 'monospace'
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _sample,
                    style: const TextStyle(color: WorkspaceColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ThemeSettings extends StatelessWidget {
  const _ThemeSettings({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final profile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    final notifier = ref.read(clarixThemeProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SettingsHeading(
          title: 'Appearance',
          description: 'Tune the app, reader, and annotation colors.',
        ),
        const SizedBox(height: 18),
        const SectionLabel(label: 'Color mode'),
        Wrap(
          spacing: 8,
          children: ThemeMode.values
              .map(
                (mode) => ChoiceChip(
                  label: Text(switch (mode) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                  selected: profile.mode == mode,
                  onSelected: (_) =>
                      notifier.setProfile(profile.copyWith(mode: mode)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        const SectionLabel(label: 'Accent'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ClarixAccent.values
              .map(
                (accent) => Tooltip(
                  message: accent.name,
                  child: InkWell(
                    onTap: () =>
                        notifier.setProfile(profile.copyWith(accent: accent)),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentFor(accent),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: profile.accent == accent
                              ? WorkspaceColors.textStrong
                              : WorkspaceColors.border,
                          width: profile.accent == accent ? 3 : 1,
                        ),
                      ),
                      child: profile.accent == accent
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.black87,
                            )
                          : null,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        const SectionLabel(label: 'Highlight'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              <int>[0xFFFFD54F, 0xFF80CBC4, 0xFFEF9A9A, 0xFFCE93D8, 0xFF90CAF9]
                  .map(
                    (color) => InkWell(
                      onTap: () => notifier.setProfile(
                        profile.copyWith(highlightColor: color),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: profile.highlightColor == color
                                ? WorkspaceColors.textStrong
                                : WorkspaceColors.border,
                            width: profile.highlightColor == color ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Text(
              'Opacity',
              style: TextStyle(color: WorkspaceColors.textMuted),
            ),
            const Spacer(),
            Text(
              '${(profile.highlightOpacity * 100).round()}%',
              style: const TextStyle(color: WorkspaceColors.textStrong),
            ),
          ],
        ),
        Slider(
          value: profile.highlightOpacity,
          min: 0.1,
          max: 0.9,
          divisions: 8,
          onChanged: (value) =>
              notifier.setProfile(profile.copyWith(highlightOpacity: value)),
        ),
        const SizedBox(height: 12),
        const SectionLabel(label: 'Reader background'),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                profile.readerBackgroundPath == null
                    ? 'No custom background selected'
                    : 'Custom image applied to the reader',
                style: const TextStyle(color: WorkspaceColors.textMuted),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _importBackground(context, profile),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Import'),
            ),
            if (profile.readerBackgroundPath != null) ...<Widget>[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove reader background',
                onPressed: () => notifier.setProfile(
                  profile.copyWith(clearReaderBackgroundPath: true),
                ),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _importBackground(
    BuildContext context,
    ClarixThemeProfile profile,
  ) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null) return;
      final stored = await ReaderBackgroundStore().importImage(path);
      await ref
          .read(clarixThemeProvider.notifier)
          .setProfile(profile.copyWith(readerBackgroundPath: stored));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not import that image.')),
        );
      }
    }
  }
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
                  .read(aiNotifierProvider.notifier)
                  .selectProvider(profile.id),
              icon: const Icon(Icons.check_circle_outline),
            ),
          IconButton(
            tooltip: 'Edit ${profile.label}',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ProviderEditorDialog(profile: profile),
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
      await ref.read(aiNotifierProvider.notifier).deleteProvider(profile.id);
    }
  }
}
