import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:clarix/src/features/tts/tts.dart';
import 'workspace_common.dart';

const String _previewText =
    'This is how this voice sounds when reading a document aloud.';

/// Settings section for on-device text-to-speech: voice-pack download and
/// the default voice/speed used everywhere "Read aloud" is invoked.
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
    final TtsModelSpec spec = TtsModelCatalog.defaultModel;
    final TtsModelInstallState install =
        state.installState[spec.id] ?? const TtsModelInstallState();
    final bool installed = install.status == TtsInstallStatus.installed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Read aloud',
          style: TextStyle(
            color: WorkspaceColors.textStrong,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Download an on-device voice to have documents read aloud from '
          'the right-click menu.',
          style: TextStyle(color: WorkspaceColors.textMuted),
        ),
        const SizedBox(height: 10),
        _buildModelRow(spec, install),
        if (installed) ...<Widget>[
          const SizedBox(height: 18),
          const Text(
            'Voice',
            style: TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildVoiceGrid(state, spec),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Text(
                'Speed',
                style: TextStyle(
                  color: WorkspaceColors.textStrong,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${state.defaultSpeed.toStringAsFixed(2)}x',
                style: const TextStyle(color: WorkspaceColors.textMuted),
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
        if (state.errorMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            state.errorMessage!,
            style: const TextStyle(color: WorkspaceColors.warning, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildModelRow(TtsModelSpec spec, TtsModelInstallState install) {
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
                  style: const TextStyle(
                    color: WorkspaceColors.warning,
                    fontSize: 12,
                  ),
                ),
              ),
            OutlinedButton.icon(
              key: const Key('download-tts-voice'),
              onPressed: () =>
                  ref.read(ttsNotifierProvider.notifier).downloadModel(spec),
              icon: const Icon(Icons.download_outlined),
              label: Text(
                '${spec.label} · ${sizeMb.toStringAsFixed(0)}MB',
              ),
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
              style: const TextStyle(color: WorkspaceColors.textMuted, fontSize: 12),
            ),
          ],
        );
      case TtsInstallStatus.installed:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.graphic_eq),
          title: Text(spec.label),
          subtitle: const Text('Installed on this device'),
          trailing: IconButton(
            key: const Key('delete-tts-voice'),
            tooltip: 'Delete ${spec.label}',
            onPressed: () =>
                ref.read(ttsNotifierProvider.notifier).deleteModel(spec),
            icon: const Icon(Icons.delete_outline),
          ),
        );
    }
  }

  Widget _buildVoiceGrid(TtsFeatureState state, TtsModelSpec spec) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int sid = 0; sid < spec.voiceCount; sid++)
          _VoiceTile(
            sid: sid,
            selected: state.defaultVoiceSid == sid,
            previewing: _previewingSid == sid,
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
    required this.onSelect,
    required this.onPreview,
  });

  final int sid;
  final bool selected;
  final bool previewing;
  final VoidCallback onSelect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? WorkspaceColors.accentSoft : WorkspaceColors.panelRaised,
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
                color: selected
                    ? WorkspaceColors.accent
                    : WorkspaceColors.textStrong,
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
