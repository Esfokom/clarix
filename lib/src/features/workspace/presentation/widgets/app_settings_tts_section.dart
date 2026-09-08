import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clarix/src/features/tts/tts.dart';

import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import 'workspace_common.dart';

const String _previewText =
    'This is how this voice sounds when reading a document aloud.';

/// Settings section for on-device text-to-speech: engine choice, voice-pack
/// download, and the default voice/speed used everywhere "Read aloud" is
/// invoked.
class TtsSettingsSection extends ConsumerStatefulWidget {
  const TtsSettingsSection({super.key});

  @override
  ConsumerState<TtsSettingsSection> createState() => _TtsSettingsSectionState();
}

class _TtsSettingsSectionState extends ConsumerState<TtsSettingsSection> {
  int? _previewingSid;

  @override
  Widget build(BuildContext context) {
    final TtsFeatureState state =
        ref.watch(ttsNotifierProvider).value ?? TtsFeatureState.initial();
    final bool isSystem = state.activeEngine == TtsEngineKind.system;
    final TtsModelSpec activeSpec = state.activeModelId == null
        ? TtsModelCatalog.defaultModel
        : TtsModelCatalog.byId(state.activeModelId!);
    final TtsModelInstallState activeInstall =
        state.installState[activeSpec.id] ?? const TtsModelInstallState();
    final bool activeInstalled = activeInstall.status == TtsInstallStatus.installed;
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Read aloud',
          style: TextStyle(
            color: colors.textStrong,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose an on-device voice pack to download, or use your system\'s '
          'built-in voice — available from the right-click "Read aloud" menu.',
          style: TextStyle(color: colors.textMuted),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              label: Text('On-device', key: Key('tts-engine-on-device')),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('System voice', key: Key('tts-engine-system')),
            ),
          ],
          selected: <bool>{isSystem},
          onSelectionChanged: (Set<bool> selection) => ref
              .read(ttsNotifierProvider.notifier)
              .setActiveEngine(
                selection.first ? TtsEngineKind.system : TtsEngineKind.kittenSherpa,
              ),
        ),
        const SizedBox(height: 14),
        if (isSystem)
          _buildSystemVoiceList(state, colors)
        else
          _buildOnDeviceSection(state, activeSpec, activeInstalled, colors),
        if (state.errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            state.errorMessage!,
            style: TextStyle(color: colors.warning, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildOnDeviceSection(
    TtsFeatureState state,
    TtsModelSpec activeSpec,
    bool activeInstalled,
    WorkspaceSurfaceTokens colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final TtsModelSpec spec in TtsModelCatalog.all) ...<Widget>[
          _buildModelRow(
            spec,
            state.installState[spec.id] ?? const TtsModelInstallState(),
            colors,
            selected: spec.id == activeSpec.id,
          ),
          const SizedBox(height: 8),
        ],
        if (activeInstalled && activeSpec.voiceCount > 1) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'Voice',
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildVoiceGrid(state, activeSpec, colors),
        ],
        if (activeInstalled) ...<Widget>[
          const SizedBox(height: 18),
          _buildSpeedSlider(state, colors),
        ],
      ],
    );
  }

  Widget _buildSystemVoiceList(
    TtsFeatureState state,
    WorkspaceSurfaceTokens colors,
  ) {
    if (state.availableSystemVoices.isEmpty) {
      return Text(
        'No system voices were found on this device.',
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final SystemTtsVoice voice in state.availableSystemVoices)
          RadioListTile<SystemTtsVoice>(
            key: Key('system-voice-${voice.name}-${voice.locale}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${voice.name} (${voice.locale})'),
            value: voice,
            groupValue: state.systemVoice,
            onChanged: (SystemTtsVoice? value) {
              if (value != null) {
                ref.read(ttsNotifierProvider.notifier).setSystemVoice(value);
              }
            },
          ),
        const SizedBox(height: 10),
        _buildSpeedSlider(state, colors),
      ],
    );
  }

  Widget _buildSpeedSlider(TtsFeatureState state, WorkspaceSurfaceTokens colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Speed',
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${state.defaultSpeed.toStringAsFixed(2)}x',
              style: TextStyle(color: colors.textMuted),
            ),
          ],
        ),
        Slider(
          value: state.defaultSpeed,
          min: 0.75,
          max: 1.5,
          divisions: 15,
          onChanged: (double value) =>
              ref.read(ttsNotifierProvider.notifier).setDefaultSpeed(value),
        ),
      ],
    );
  }

  Widget _buildModelRow(
    TtsModelSpec spec,
    TtsModelInstallState install,
    WorkspaceSurfaceTokens colors, {
    required bool selected,
  }) {
    final double sizeMb = spec.approxArchiveSizeBytes / 1000 / 1000;
    switch (install.status) {
      case TtsInstallStatus.notInstalled:
      case TtsInstallStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (install.status == TtsInstallStatus.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  install.errorMessage ?? 'Download failed.',
                  style: TextStyle(color: colors.warning, fontSize: 12),
                ),
              ),
            OutlinedButton.icon(
              key: Key('download-tts-voice-${spec.id}'),
              onPressed: () =>
                  ref.read(ttsNotifierProvider.notifier).downloadModel(spec),
              icon: const Icon(Icons.download_outlined),
              label: Text('${spec.label} · ${sizeMb.toStringAsFixed(0)}MB'),
            ),
          ],
        );
      case TtsInstallStatus.downloading:
      case TtsInstallStatus.extracting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LinearProgressIndicator(
              value: install.status == TtsInstallStatus.extracting
                  ? null
                  : install.progress,
            ),
            const SizedBox(height: 6),
            Text(
              install.status == TtsInstallStatus.extracting
                  ? 'Extracting…'
                  : 'Downloading ${spec.label}… ${(install.progress * 100).round()}%',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
        );
      case TtsInstallStatus.installed:
        return Material(
          color: selected ? colors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: ListTile(
            key: Key('tts-model-row-${spec.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            ),
            title: Text(spec.label),
            subtitle: const Text('Installed on this device'),
            onTap: () =>
                ref.read(ttsNotifierProvider.notifier).setActiveModel(spec),
            trailing: IconButton(
              key: Key('delete-tts-voice-${spec.id}'),
              tooltip: 'Delete ${spec.label}',
              onPressed: () =>
                  ref.read(ttsNotifierProvider.notifier).deleteModel(spec),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        );
    }
  }

  Widget _buildVoiceGrid(
    TtsFeatureState state,
    TtsModelSpec spec,
    WorkspaceSurfaceTokens colors,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int sid = 0; sid < spec.voiceCount; sid++)
          _VoiceTile(
            sid: sid,
            selected: state.defaultVoiceSid == sid,
            previewing: _previewingSid == sid,
            colors: colors,
            onSelect: () =>
                ref.read(ttsNotifierProvider.notifier).setDefaultVoice(sid),
            onPreview: () => _preview(sid),
          ),
      ],
    );
  }

  Future<void> _preview(int sid) async {
    if (_previewingSid != null) return;
    setState(() => _previewingSid = sid);
    try {
      await ref.read(ttsNotifierProvider.notifier).previewVoice(sid, _previewText);
    } finally {
      if (mounted) setState(() => _previewingSid = null);
    }
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.sid,
    required this.selected,
    required this.previewing,
    required this.colors,
    required this.onSelect,
    required this.onPreview,
  });

  final int sid;
  final bool selected;
  final bool previewing;
  final WorkspaceSurfaceTokens colors;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? colors.accentSoft : colors.panelRaised,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: Key('tts-voice-$sid'),
      borderRadius: BorderRadius.circular(8),
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Voice ${sid + 1}',
              style: TextStyle(
                color: selected ? colors.accent : colors.textStrong,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              height: 28,
              child: previewing
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: Key('tts-voice-preview-$sid'),
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: 'Preview',
                      onPressed: onPreview,
                      icon: const Icon(Icons.play_arrow),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
