import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'pdf_utilities_dialogs.dart';
import 'workspace_common.dart';
import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/ai/presentation/study_mode_side_pane.dart';

class QuickstartSurface extends ConsumerWidget {
  const QuickstartSurface({required this.state, super.key});

  final WorkspaceFeatureState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: const Color(0xFF2F2F2F),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 40, 40, 28),
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
                              color: Color(0xFFE3E0DC),
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              height: 1.12,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Open a PDF or choose a utility to get started.',
                            style: GoogleFonts.roboto(
                              color: const Color(0xFFA6A6A6),
                              fontSize: 14,
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
                    const SizedBox(width: 8),
                    ShadButton.outline(
                      height: 34,
                      leading: const QaMergedIcon(size: 15),
                      onPressed: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .selectRightToolWindow(RightToolWindow.studyMode),
                      child: const Text('Enter Study Mode'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _QuickstartSectionLabel(label: 'Utilities'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  child: GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    // At the narrow supported width, a square tile is slightly
                    // taller than this fixed-height grid after its gutters.
                    childAspectRatio: 1.02,
                    children: <Widget>[
                      _UtilityCard(
                        icon: LucideIcons.files,
                        title: 'Combine PDFs',
                        detail:
                            'Order multiple PDFs and save them as one file.',
                        onTap: () => showCombinePdfDialog(context),
                      ),
                      _UtilityCard(
                        icon: LucideIcons.fileOutput,
                        title: 'Convert to PDF',
                        detail: 'Create PDFs from documents, text, and images.',
                        onTap: () => showConvertToPdfDialog(context),
                      ),
                      _UtilityCard(
                        icon: LucideIcons.fileStack,
                        title: 'Extract pages',
                        detail: 'Choose page ranges and save a new PDF.',
                        onTap: () => showExtractPagesDialog(context),
                      ),
                      _UtilityCard(
                        icon: LucideIcons.share2,
                        title: 'Export PDF',
                        detail:
                            'Export content to Markdown, Word, or PowerPoint.',
                        onTap: () => showExportPdfDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const _QuickstartSectionLabel(label: 'Recent documents'),
                const SizedBox(height: 12),
                Expanded(
                  child: state.session.recentFiles.isEmpty
                      ? const Center(child: Text('No recent PDFs yet.'))
                      : ListView.separated(
                          itemCount: state.session.recentFiles.length,
                          separatorBuilder: (_, int index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (BuildContext context, int index) =>
                              _QuickstartRecentTile(
                                path: state.session.recentFiles[index],
                              ),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF343434),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF454545)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      title,
                      style: GoogleFonts.roboto(
                        color: const Color(0xFFE3E0DC),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
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
