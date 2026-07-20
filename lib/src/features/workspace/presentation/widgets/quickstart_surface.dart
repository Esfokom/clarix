import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

class QuickstartSurface extends ConsumerWidget {
  const QuickstartSurface({required this.state, super.key});

  final WorkspaceFeatureState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Welcome to Clarix',
                      style: TextStyle(
                        color: WorkspaceColors.textStrong,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Open a PDF or continue from a recent document.',
                      style: TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              ShadButton.secondary(
                height: 34,
                leading: const Icon(LucideIcons.cpu, size: 15),
                onPressed: () => ref
                    .read(workspaceNotifierProvider.notifier)
                    .toggleProviderSettings(true),
                child: const Text('AI providers'),
              ),
              const SizedBox(width: 8),
              ShadButton(
                height: 34,
                leading: const Icon(LucideIcons.filePlus2, size: 15),
                onPressed: () => ref
                    .read(workspaceNotifierProvider.notifier)
                    .pickAndOpenPdfs(),
                child: const Text('Open PDF'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: SurfaceBlock(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SectionLabel(label: 'Recent documents'),
                        Expanded(
                          child: state.session.recentFiles.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No recent PDFs yet.',
                                    style: TextStyle(
                                      color: WorkspaceColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: state.session.recentFiles.length,
                                  separatorBuilder: (_, int index) =>
                                      const SizedBox(height: 8),
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                        final String path =
                                            state.session.recentFiles[index];
                                        return _QuickstartRecentTile(
                                          path: path,
                                        );
                                      },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: SurfaceBlock(
                          padding: const EdgeInsets.all(14),
                          child: _StatusPanel(
                            title: 'Session',
                            value: state.session.restorePreviousSession
                                ? 'Restore enabled'
                                : 'Fresh launch mode',
                            detail: state.session.restorePreviousSession
                                ? 'Valid tabs reopen automatically.'
                                : 'Closing with tabs asks for confirmation.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SurfaceBlock(
                          padding: const EdgeInsets.all(14),
                          child: _StatusPanel(
                            title: 'AI',
                            value: state.aiState.statusMessage,
                            detail:
                                state.aiState.embeddingReady &&
                                    state.aiState.vectorStoreReady
                                ? 'Grounded PDF chat is ready after indexing.'
                                : 'Install local models to enable retrieval.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickstartRecentTile extends ConsumerWidget {
  const _QuickstartRecentTile({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String label = path.split(RegExp(r'[\\/]')).last;
    return GestureDetector(
      onTap: () =>
          ref.read(workspaceNotifierProvider.notifier).reopenRecent(path),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WorkspaceColors.panelRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WorkspaceColors.border),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WorkspaceColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.fileText,
                size: 16,
                color: WorkspaceColors.textStrong,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkspaceColors.textStrong,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkspaceColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.arrowRight,
              size: 14,
              color: WorkspaceColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: WorkspaceColors.textFaint,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            color: WorkspaceColors.textStrong,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          style: const TextStyle(
            color: WorkspaceColors.textMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
