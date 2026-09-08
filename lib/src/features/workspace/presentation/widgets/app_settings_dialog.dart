import 'dart:async';

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
import 'app_settings_tts_section.dart';
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
    final ClarixThemeProfile profile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      profile,
      context,
    );
    return Dialog(
      backgroundColor: colors.panel,
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
                        Expanded(
                          child: Text(
                            'App settings',
                            style: TextStyle(
                              color: colors.textStrong,
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
                      colors: colors,
                    ),
                    Divider(height: 25, color: colors.border),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 8),
                        child: _tab == 0
                            ? _FontSettings(ref: ref, colors: colors)
                            : _tab == 1
                            ? _ThemeSettings(ref: ref, colors: colors)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _SettingsHeading(
                                    title: 'AI models',
                                    description:
                                        'Choose an on-device model or configure an online provider.',
                                    colors: colors,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Local',
                                    style: TextStyle(
                                      color: colors.textStrong,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (aiState.localModels.isEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        key: const Key('download-gemma-4'),
                                        onPressed: () => ref
                                            .read(aiNotifierProvider.notifier)
                                            .downloadGemma4(),
                                        icon: const Icon(
                                          Icons.download_outlined,
                                        ),
                                        label: const Text(
                                          'Download Gemma 4 E2B',
                                        ),
                                      ),
                                    )
                                  else
                                    ...aiState.localModels.map(
                                      (LocalModelProfile model) => ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                        leading: Image.asset(
                                          'assets/images/gemma-color.png',
                                          width: 28,
                                          height: 28,
                                        ),
                                        title: Text(model.label),
                                        subtitle: const Text('On this device'),
                                        trailing: IconButton(
                                          key: Key(
                                            'delete-local-model-${model.id}',
                                          ),
                                          tooltip: 'Delete ${model.label}',
                                          onPressed: () => ref
                                              .read(aiNotifierProvider.notifier)
                                              .deleteLocalModel(model),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Online',
                                    style: TextStyle(
                                      color: colors.textStrong,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (aiState.providerProfiles.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No providers configured',
                                          style: TextStyle(
                                            color: colors.textMuted,
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
                                  const _VoiceInputSettings(),
                                  const SizedBox(height: 24),
                                  const TtsSettingsSection(),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Storage',
                                    style: TextStyle(
                                      color: colors.textStrong,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Manage locally stored AI conversations.',
                                    style: TextStyle(
                                      color: colors.textMuted,
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

class _VoiceInputSettings extends ConsumerStatefulWidget {
  const _VoiceInputSettings();

  @override
  ConsumerState<_VoiceInputSettings> createState() =>
      _VoiceInputSettingsState();
}

class _VoiceInputSettingsState extends ConsumerState<_VoiceInputSettings> {
  static const String _systemDefaultId = '__system_default__';

  List<VoiceInputDevice> _devices = const <VoiceInputDevice>[];
  String? _selectedDeviceId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final recorder = ref.read(voiceRecorderProvider);
    final store = ref.read(voiceInputSettingsStoreProvider);
    try {
      final List<VoiceInputDevice> devices = await recorder.listInputDevices();
      String? selectedDeviceId = await store.readSelectedDeviceId();
      if (selectedDeviceId != null &&
          !devices.any(
            (VoiceInputDevice item) => item.id == selectedDeviceId,
          )) {
        selectedDeviceId = null;
        await store.saveSelectedDeviceId(null);
      }
      if (selectedDeviceId != null) {
        await recorder.selectInputDevice(selectedDeviceId);
      }
      if (mounted) {
        setState(() {
          _devices = devices;
          _selectedDeviceId = selectedDeviceId;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(String? value) {
    if (value == null) return;
    unawaited(_saveSelection(value));
  }

  Future<void> _saveSelection(String value) async {
    final String? deviceId = value == _systemDefaultId ? null : value;
    try {
      await ref.read(voiceRecorderProvider).selectInputDevice(deviceId);
      await ref
          .read(voiceInputSettingsStoreProvider)
          .saveSelectedDeviceId(deviceId);
      if (mounted) setState(() => _selectedDeviceId = deviceId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not select microphone: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ClarixThemeProfile profile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      profile,
      context,
    );
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        'Voice input',
        style: TextStyle(
          color: colors.textStrong,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Choose the microphone used for voice questions.',
        style: TextStyle(color: colors.textMuted),
      ),
      const SizedBox(height: 10),
      if (_loading)
        const SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else
        DropdownButtonFormField<String>(
          key: const Key('voice-input-device-setting'),
          initialValue: _selectedDeviceId ?? _systemDefaultId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Microphone'),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: _systemDefaultId,
              child: Text('System default microphone'),
            ),
            ..._devices.map(
              (VoiceInputDevice device) => DropdownMenuItem<String>(
                value: device.id,
                child: Text(device.label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: _select,
        ),
    ],
    );
  }
}

class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({
    required this.selected,
    required this.onSelected,
    required this.colors,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  final WorkspaceSurfaceTokens colors;

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
            ? colors.textStrong
            : colors.textMuted,
        backgroundColor: active
            ? colors.panelRaised
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
  const _SettingsHeading({
    required this.title,
    required this.description,
    required this.colors,
  });
  final String title;
  final String description;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        style: TextStyle(
          color: colors.textStrong,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        description,
        style: TextStyle(color: colors.textMuted),
      ),
    ],
  );
}

class _FontSettings extends StatelessWidget {
  const _FontSettings({required this.ref, required this.colors});
  final WidgetRef ref;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final profile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SettingsHeading(
          title: 'Interface font',
          description: 'Choose the typeface used throughout Clarix.',
          colors: colors,
        ),
        const SizedBox(height: 18),
        ...ClarixFont.values.map(
          (font) => _FontOption(
            font: font,
            selected: profile.font == font,
            onTap: () => ref
                .read(clarixThemeProvider.notifier)
                .setProfile(profile.copyWith(font: font)),
            colors: colors,
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
    required this.colors,
  });
  final ClarixFont font;
  final bool selected;
  final VoidCallback onTap;
  final WorkspaceSurfaceTokens colors;

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
              ? colors.accentSoft
              : colors.panelRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? colors.accentBorder
                : colors.border,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? colors.textStrong
                  : colors.textFaint,
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
                      color: colors.textStrong,
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
                    style: TextStyle(color: colors.textMuted),
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
  const _ThemeSettings({required this.ref, required this.colors});
  final WidgetRef ref;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final profile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    final notifier = ref.read(clarixThemeProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SettingsHeading(
          title: 'Appearance',
          description: 'Tune the app, reader, and annotation colors.',
          colors: colors,
        ),
        const SizedBox(height: 18),
        SectionLabel(label: 'Color mode', colors: colors),
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
        SectionLabel(label: 'Accent', colors: colors),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ClarixAccent.values
              .map(
                (accent) => Tooltip(
                  message: accent.name,
                  child: InkWell(
                    onTap: () => accent == ClarixAccent.custom
                        ? _pickCustomAccent(context, profile, colors)
                        : notifier.setProfile(profile.copyWith(accent: accent)),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentFor(accent),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: profile.accent == accent
                              ? colors.textStrong
                              : colors.border,
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
        SectionLabel(label: 'Highlight', colors: colors),
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
                                ? colors.textStrong
                                : colors.border,
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
            Text(
              'Opacity',
              style: TextStyle(color: colors.textMuted),
            ),
            const Spacer(),
            Text(
              '${(profile.highlightOpacity * 100).round()}%',
              style: TextStyle(color: colors.textStrong),
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
        SectionLabel(label: 'Reader background', colors: colors),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                profile.readerBackgroundPath == null
                    ? 'No custom background selected'
                    : 'Custom image applied to the reader',
                style: TextStyle(color: colors.textMuted),
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
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text('Invert background image for dark mode'),
          value: profile.readerBackgroundInverted,
          onChanged: profile.readerBackgroundPath == null
              ? null
              : (bool? value) => notifier.setProfile(
                  profile.copyWith(readerBackgroundInverted: value ?? false),
                ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: const Text('Warm paper page background'),
          value: profile.readerBookBackgroundOverride,
          onChanged: (bool? value) => notifier.setProfile(
            profile.copyWith(readerBookBackgroundOverride: value ?? false),
          ),
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

  Future<void> _pickCustomAccent(
    BuildContext context,
    ClarixThemeProfile profile,
    WorkspaceSurfaceTokens colors,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: (profile.customAccentColor ?? 0xFFE4E4E7)
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2)
          .toUpperCase(),
    );
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final int? parsed = _parseHexColor(controller.text);
          return AlertDialog(
            title: const Text('Custom accent color'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: parsed != null ? Color(parsed) : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('custom-accent-hex-field'),
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixText: '#',
                      hintText: 'RRGGBB',
                    ),
                    maxLength: 6,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                key: const Key('custom-accent-confirm'),
                onPressed: parsed == null
                    ? null
                    : () => Navigator.of(context).pop(parsed),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    if (picked != null) {
      await ref.read(clarixThemeProvider.notifier).setProfile(
        profile.copyWith(accent: ClarixAccent.custom, customAccentColor: picked),
      );
    }
  }
}

int? _parseHexColor(String text) {
  final String cleaned = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return null;
  return int.parse('FF$cleaned', radix: 16);
}

class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.profile, required this.isDefault});

  final AiProviderProfile profile;
  final bool isDefault;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ClarixThemeProfile themeProfile =
        ref.watch(clarixThemeProvider).value ?? ClarixThemeProfile();
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      themeProfile,
      context,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              _providerIcon(profile.label),
              width: 28,
              height: 28,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        profile.label,
                        style: TextStyle(
                          color: colors.textStrong,
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
                  style: TextStyle(color: colors.textMuted),
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

  String _providerIcon(String label) {
    final String normalized = label.toLowerCase();
    if (normalized.contains('deepseek')) return 'assets/images/deepseek.png';
    if (normalized.contains('openai')) return 'assets/images/openai.png';
    return 'assets/images/openai.png';
  }
}
