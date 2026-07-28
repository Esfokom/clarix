import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'pdf_utilities_dialogs.dart';
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
              const Expanded(
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
                    SizedBox(height: 6),
                    Text(
                      'Open a PDF or use a local document utility.',
                      style: TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
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
          const SizedBox(height: 18),
          const _QuickstartSectionLabel(label: 'Utilities'),
          const SizedBox(height: 10),
          SizedBox(
            height: 208,
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 4.1,
              children: <Widget>[
                _UtilityCard(
                  icon: LucideIcons.files,
                  title: 'Combine PDFs',
                  detail: 'Order multiple PDFs and save them as one file.',
                  onTap: () => showCombinePdfDialog(context),
                ),
                const _UtilityCard(
                  icon: LucideIcons.fileOutput,
                  title: 'Convert to PDF',
                  detail: 'Create PDFs from documents, text, and images.',
                ),
                _UtilityCard(
                  icon: LucideIcons.fileStack,
                  title: 'Extract pages',
                  detail: 'Choose page ranges and save a new PDF.',
                  onTap: () => showExtractPagesDialog(context),
                ),
                const _UtilityCard(
                  icon: LucideIcons.share2,
                  title: 'Export PDF',
                  detail: 'Export content to Markdown, Word, or PowerPoint.',
                ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 190,
            child: SurfaceBlock(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _QuickstartSectionLabel(label: 'Recent documents'),
                  const SizedBox(height: 8),
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
                                const SizedBox(height: 6),
                            itemBuilder: (BuildContext context, int index) {
                              return _QuickstartRecentTile(
                                path: state.session.recentFiles[index],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickstartSectionLabel extends StatelessWidget {
  const _QuickstartSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: WorkspaceColors.textFaint,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _UtilityCard extends StatelessWidget {
  const _UtilityCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: WorkspaceColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WorkspaceColors.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: enabled
                        ? WorkspaceColors.accentSoft
                        : WorkspaceColors.panelRaised,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: enabled
                        ? WorkspaceColors.textStrong
                        : WorkspaceColors.textFaint,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          color: enabled
                              ? WorkspaceColors.textStrong
                              : WorkspaceColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WorkspaceColors.textMuted,
                          fontSize: 10.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (enabled)
                  const Icon(
                    LucideIcons.arrowUpRight,
                    size: 15,
                    color: WorkspaceColors.textFaint,
                  )
                else
                  const Text(
                    'Soon',
                    style: TextStyle(
                      color: WorkspaceColors.textFaint,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: WorkspaceColors.panelRaised,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: WorkspaceColors.border),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              LucideIcons.fileText,
              size: 15,
              color: WorkspaceColors.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WorkspaceColors.textStrong,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: WorkspaceColors.textFaint,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              LucideIcons.arrowRight,
              size: 13,
              color: WorkspaceColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}
