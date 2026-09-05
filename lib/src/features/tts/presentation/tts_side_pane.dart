import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme_controller.dart';
import '../../../core/theme_profile.dart';
import '../../../core/workspace_surface_tokens.dart';
import '../application/tts_feature_state.dart';
import '../application/tts_providers.dart';
import '../domain/tts_models.dart';
import '../infrastructure/tts_model_catalog.dart';

class TtsSidePane extends ConsumerWidget {
  const TtsSidePane({
    required this.documentId,
    required this.onCollapse,
    this.onNavigateToPage,
    super.key,
  });

  final String documentId;
  final VoidCallback onCollapse;
  final ValueChanged<int>? onNavigateToPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    final TtsFeatureState state =
        ref.watch(ttsNotifierProvider).value ?? TtsFeatureState.initial();
    ref.listen<TtsPlaybackState>(
      ttsNotifierProvider.select(
        (AsyncValue<TtsFeatureState> value) =>
            value.value?.playback ?? const TtsPlaybackState(),
      ),
      (TtsPlaybackState? previous, TtsPlaybackState next) {
        final int? page = next.currentPage;
        if (page != null && page != previous?.currentPage) {
          onNavigateToPage?.call(page);
        }
      },
    );

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.panel),
      child: Column(
        children: <Widget>[
          _buildHeader(colors),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (state.errorMessage != null) ...<Widget>[
                    _errorBanner(colors, state.errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (state.playback.status != TtsPlaybackStatus.idle) ...<Widget>[
                    _buildPlaybackCard(context, ref, colors, state),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Voice packs',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final TtsModelSpec spec in TtsModelCatalog.all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildModelCard(context, ref, colors, state, spec),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(WorkspaceSurfaceTokens colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: <Widget>[
        Icon(LucideIcons.headphones, size: 16, color: colors.textStrong),
        const SizedBox(width: 8),
        Text(
          'Listen',
          style: TextStyle(
            color: colors.textStrong,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        ShadIconButton.ghost(
          icon: const Icon(LucideIcons.panelRightClose, size: 16),
          onPressed: onCollapse,
        ),
      ],
    ),
  );

  Widget _buildPlaybackCard(
    BuildContext context,
    WidgetRef ref,
    WorkspaceSurfaceTokens colors,
    TtsFeatureState state,
  ) {
    final TtsPlaybackState playback = state.playback;
    final bool preparing = playback.status == TtsPlaybackStatus.preparing;
    final bool speaking = playback.status == TtsPlaybackStatus.speaking;
    final double progress = playback.segmentTotal == 0
        ? 0
        : (playback.segmentIndex + 1) / playback.segmentTotal;
    return _TtsCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            preparing
                ? 'Preparing…'
                : 'Reading page ${playback.currentPage ?? '—'}',
            style: TextStyle(color: colors.textStrong, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: playback.segmentTotal == 0 ? null : progress,
          ),
          if (playback.segmentTotal > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Segment ${playback.segmentIndex + 1} of ${playback.segmentTotal}',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: ShadButton.outline(
                  onPressed: () => ref.read(ttsNotifierProvider.notifier).stop(),
                  child: const Text('Stop'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ShadButton(
                  onPressed: preparing
                      ? null
                      : () => speaking
                          ? ref.read(ttsNotifierProvider.notifier).pause()
                          : ref.read(ttsNotifierProvider.notifier).resume(),
                  child: Text(speaking ? 'Pause' : 'Resume'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(
    BuildContext context,
    WidgetRef ref,
    WorkspaceSurfaceTokens colors,
    TtsFeatureState state,
    TtsModelSpec spec,
  ) {
    final TtsModelInstallState install =
        state.installState[spec.id] ?? const TtsModelInstallState();
    final bool selected = state.selectedModelId == spec.id;
    final double sizeMb = spec.approxArchiveSizeBytes / 1000 / 1000;

    return _TtsCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      spec.label,
                      style: TextStyle(
                        color: colors.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${spec.description} · ${sizeMb.toStringAsFixed(0)}MB',
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(LucideIcons.checkCircle2, size: 16, color: colors.accent),
            ],
          ),
          const SizedBox(height: 8),
          if (install.status == TtsInstallStatus.downloading ||
              install.status == TtsInstallStatus.extracting) ...<Widget>[
            LinearProgressIndicator(
              value: install.status == TtsInstallStatus.extracting
                  ? null
                  : install.progress,
            ),
            const SizedBox(height: 6),
            Text(
              install.status == TtsInstallStatus.extracting
                  ? 'Extracting…'
                  : 'Downloading… ${(install.progress * 100).round()}%',
              style: TextStyle(color: colors.textMuted, fontSize: 11),
            ),
          ] else if (install.status == TtsInstallStatus.installed) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: ShadButton(
                    enabled: !selected,
                    onPressed: selected
                        ? null
                        : () => ref
                            .read(ttsNotifierProvider.notifier)
                            .selectModel(spec.id),
                    child: Text(selected ? 'Selected' : 'Use this voice'),
                  ),
                ),
                const SizedBox(width: 8),
                ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  onPressed: () => ref
                      .read(ttsNotifierProvider.notifier)
                      .deleteModel(spec),
                ),
              ],
            ),
            if (selected) ...<Widget>[
              const SizedBox(height: 8),
              ShadButton(
                onPressed: () =>
                    ref.read(ttsNotifierProvider.notifier).play(documentId),
                child: const Text('Read this document'),
              ),
            ],
          ] else ...<Widget>[
            if (install.status == TtsInstallStatus.failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  install.errorMessage ?? 'Download failed.',
                  style: TextStyle(color: colors.warning, fontSize: 11),
                ),
              ),
            ShadButton.outline(
              onPressed: () =>
                  ref.read(ttsNotifierProvider.notifier).downloadModel(spec),
              child: const Text('Download'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorBanner(WorkspaceSurfaceTokens colors, String message) => _TtsCard(
    colors: colors,
    child: Text(message, style: TextStyle(color: colors.warning, fontSize: 12)),
  );
}

class _TtsCard extends StatelessWidget {
  const _TtsCard({required this.colors, required this.child});

  final WorkspaceSurfaceTokens colors;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: colors.panelRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.border),
    ),
    child: child,
  );
}
