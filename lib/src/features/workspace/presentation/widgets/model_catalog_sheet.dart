import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

bool shouldShowModelTransferControls(DownloadTaskStatus status) {
  return status == DownloadTaskStatus.running ||
      status == DownloadTaskStatus.validating;
}

class ModelCatalogSheet extends ConsumerWidget {
  const ModelCatalogSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WorkspaceFeatureState state =
        ref.watch(workspaceNotifierProvider).value!;

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      child: SmoothClipRRect(
        smoothness: 0.88,
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: WorkspaceColors.border),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: WorkspaceColors.panel),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Model catalog',
                        style: TextStyle(
                          color: WorkspaceColors.textStrong,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ShadIconButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      icon: const Icon(LucideIcons.x, size: 14),
                      onPressed: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .toggleModelCatalog(false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.separated(
                    itemCount: state.catalog.length,
                    separatorBuilder: (_, int index) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final ModelCatalogItem item = state.catalog[index];
                      final DownloadTaskState task =
                          state.downloads[item.id] ??
                              DownloadTaskState.initial(item.id);
                      return _ModelCatalogCard(item: item, task: task);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelCatalogCard extends ConsumerWidget {
  const _ModelCatalogCard({
    required this.item,
    required this.task,
  });

  final ModelCatalogItem item;
  final DownloadTaskState task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isBusy = shouldShowModelTransferControls(task.status);
    final bool isInstalled =
        item.installState == ModelInstallState.installed ||
            task.status == DownloadTaskStatus.completed;
    final bool canReveal =
        isInstalled && (item.installedPath ?? task.installedPath) != null;
    final int visibleProgress = isInstalled && !isBusy ? 100 : task.progress;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WorkspaceColors.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkspaceColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.label,
            style: const TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((item.description ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              item.description!,
              style: const TextStyle(
                color: WorkspaceColors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${item.family} | ${_formatBytes(item.sizeBytes)} | ${item.platforms.join(', ')}',
            style: const TextStyle(
              color: WorkspaceColors.textFaint,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 10),
          if (isBusy) ...<Widget>[
            LinearProgressIndicator(
              value: visibleProgress / 100,
              minHeight: 4,
              backgroundColor: WorkspaceColors.border,
              color: WorkspaceColors.accent,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: <Widget>[
              Text(
                '$visibleProgress%',
                style: const TextStyle(
                  color: WorkspaceColors.textStrong,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                _formatProgress(task, isInstalled: isInstalled),
                style: const TextStyle(
                  color: WorkspaceColors.textFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: ShadButton(
                  height: 32,
                  onPressed: isBusy
                      ? null
                      : () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .installModel(item),
                  child: Text(
                    item.installState == ModelInstallState.installed
                        ? 'Reinstall'
                        : 'Download',
                  ),
                ),
              ),
              if (canReveal) ...<Widget>[
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .openModelLocation(item),
                  child: const Text('Open folder'),
                ),
              ],
              if (isBusy) ...<Widget>[
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  onPressed: task.status == DownloadTaskStatus.running
                      ? () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .pauseDownload(item.id)
                      : null,
                  child: const Text('Pause'),
                ),
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .cancelDownload(item.id),
                  child: const Text('Cancel'),
                ),
              ],
              if (task.status == DownloadTaskStatus.paused ||
                  task.status == DownloadTaskStatus.failed) ...<Widget>[
                const SizedBox(width: 8),
                ShadButton.outline(
                  height: 32,
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .cancelDownload(item.id),
                  child: const Text('Clear'),
                ),
              ],
            ],
          ),
          if (task.errorMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              task.errorMessage!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WorkspaceColors.textMuted,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _statusLabel(isInstalled: isInstalled),
            style: const TextStyle(
              color: WorkspaceColors.textFaint,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    final double gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  String _formatProgress(
    DownloadTaskState task, {
    required bool isInstalled,
  }) {
    if (isInstalled && task.downloadedBytes == 0) {
      return _formatMegabytes(item.sizeBytes);
    }
    return '${_formatMegabytes(task.downloadedBytes)} / '
        '${_formatMegabytes(task.totalBytes ?? 0)}';
  }

  String _formatMegabytes(int bytes) {
    final double mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  String _statusLabel({required bool isInstalled}) {
    if (isInstalled && task.status == DownloadTaskStatus.idle) {
      return 'local file';
    }
    if (isInstalled) {
      return 'installed';
    }
    return task.status.name;
  }
}
