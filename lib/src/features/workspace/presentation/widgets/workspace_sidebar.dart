import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

class WorkspaceSidebar extends ConsumerWidget {
  const WorkspaceSidebar({
    required this.state,
    required this.activeTab,
    required this.onOpenSettings,
    super.key,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState? activeTab;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 224,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: WorkspaceColors.panel),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: WorkspaceColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.bookOpenText,
                      color: WorkspaceColors.textStrong,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Clarix',
                          style: TextStyle(
                            color: WorkspaceColors.textStrong,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'PDF workspace',
                          style: TextStyle(
                            color: WorkspaceColors.textFaint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Settings',
                    child: ShadIconButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      icon: const Icon(LucideIcons.settings, size: 15),
                      onPressed: onOpenSettings,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: WorkspaceColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: <Widget>[
                  if (activeTab != null) ...<Widget>[
                    _SidebarPaneToggle(selected: state.session.sidebarPane),
                    const SizedBox(height: 12),
                    SectionLabel(
                      label: state.session.sidebarPane == SidebarPane.outline
                          ? 'Outline'
                          : 'Pages',
                    ),
                    SizedBox(
                      height: 172,
                      child: state.session.sidebarPane == SidebarPane.outline
                          ? OutlinePane(
                              outline:
                                  state.outlines[activeTab!.id] ??
                                  const <OutlineNodeState>[],
                            )
                          : ThumbnailPane(tab: activeTab!),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SectionLabel(label: 'Open tabs'),
                  if (state.session.tabs.isEmpty)
                    const SidebarEmpty(message: 'No open PDFs')
                  else
                    for (final DocumentTabState tab in state.session.tabs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _SidebarTabTile(
                          tab: tab,
                          selected: tab.id == state.session.activeTabId,
                        ),
                      ),
                ],
              ),
            ),
            const Divider(height: 1, color: WorkspaceColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Restore session',
                          style: TextStyle(
                            color: WorkspaceColors.textStrong,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.session.restorePreviousSession
                              ? 'Reopen previous tabs'
                              : 'Start fresh',
                          style: const TextStyle(
                            color: WorkspaceColors.textFaint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ShadSwitch(
                    value: state.session.restorePreviousSession,
                    onChanged: (bool value) => ref
                        .read(workspaceNotifierProvider.notifier)
                        .toggleRestorePreviousSession(value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarPaneToggle extends ConsumerWidget {
  const _SidebarPaneToggle({required this.selected});

  final SidebarPane selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: WorkspaceColors.panelRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WorkspaceColors.border),
      ),
      child: Row(
        children: SidebarPane.values
            .map((SidebarPane pane) {
              final bool isSelected = pane == selected;
              final String label = pane == SidebarPane.thumbnails
                  ? 'Pages'
                  : 'Outline';
              final IconData icon = pane == SidebarPane.thumbnails
                  ? LucideIcons.layoutGrid
                  : LucideIcons.listTree;
              return Expanded(
                child: GestureDetector(
                  onTap: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .setSidebarPane(pane),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? WorkspaceColors.accentSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(icon, size: 12, color: WorkspaceColors.textStrong),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: const TextStyle(
                            color: WorkspaceColors.textStrong,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _SidebarTabTile extends ConsumerWidget {
  const _SidebarTabTile({required this.tab, required this.selected});

  final DocumentTabState tab;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () =>
          ref.read(workspaceNotifierProvider.notifier).setActiveTab(tab.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: selected ? WorkspaceColors.panelRaised : WorkspaceColors.panel,
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
              tab.isMissingFile
                  ? LucideIcons.triangleAlert
                  : LucideIcons.fileText,
              size: 14,
              color: tab.isMissingFile
                  ? WorkspaceColors.warning
                  : WorkspaceColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkspaceColors.textStrong,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tab.isMissingFile
                        ? 'Missing file'
                        : 'Page ${tab.currentPage}${tab.pageCountHint == null ? '' : ' / ${tab.pageCountHint}'}',
                    style: const TextStyle(
                      color: WorkspaceColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            ShadIconButton.ghost(
              width: 24,
              height: 24,
              padding: EdgeInsets.zero,
              icon: const Icon(LucideIcons.x, size: 13),
              onPressed: () =>
                  ref.read(workspaceNotifierProvider.notifier).closeTab(tab.id),
            ),
          ],
        ),
      ),
    );
  }
}

class ThumbnailPane extends ConsumerWidget {
  const ThumbnailPane({required this.tab, super.key});

  final DocumentTabState tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab.isMissingFile) {
      return const SizedBox.shrink();
    }

    return PdfDocumentViewBuilder(
      documentRef: ref.watch(pdfDocumentRefProvider(tab.filePath)),
      builder: (BuildContext context, PdfDocument? document) {
        if (document == null) {
          return const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final int currentPage = tab.currentPage;
        final int pageCount = document.pages.length;
        final int start = (currentPage - 4).clamp(1, pageCount);
        final int end = (currentPage + 4).clamp(1, pageCount);

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: end - start + 1,
          itemBuilder: (BuildContext context, int index) {
            final int pageNumber = start + index;
            final bool selected = pageNumber == currentPage;
            return GestureDetector(
              onTap: () => ref
                  .read(workspaceNotifierProvider.notifier)
                  .updateViewerState(tabId: tab.id, currentPage: pageNumber),
              child: Container(
                width: 76,
                margin: const EdgeInsets.only(right: 8),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: WorkspaceColors.viewerBackground,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? WorkspaceColors.accentBorder
                                : WorkspaceColors.border,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: PdfPageView(
                            document: document,
                            pageNumber: pageNumber,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$pageNumber',
                      style: const TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class OutlinePane extends StatelessWidget {
  const OutlinePane({required this.outline, super.key});

  final List<OutlineNodeState> outline;

  @override
  Widget build(BuildContext context) {
    if (outline.isEmpty) {
      return const Center(
        child: Text(
          'Outline appears after the document loads.',
          style: TextStyle(color: WorkspaceColors.textFaint, fontSize: 10.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      children: outline
          .map(
            (OutlineNodeState node) => _OutlineNodeTile(node: node, depth: 0),
          )
          .toList(growable: false),
    );
  }
}

class _OutlineNodeTile extends StatelessWidget {
  const _OutlineNodeTile({required this.node, required this.depth});

  final OutlineNodeState node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.only(left: depth * 10.0),
        childrenPadding: EdgeInsets.zero,
        collapsedIconColor: WorkspaceColors.textMuted,
        iconColor: WorkspaceColors.textMuted,
        title: Text(
          node.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: WorkspaceColors.textStrong,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: node.pageNumber == null
            ? null
            : Text(
                'Page ${node.pageNumber}',
                style: const TextStyle(
                  color: WorkspaceColors.textFaint,
                  fontSize: 10,
                ),
              ),
        children: node.children
            .map(
              (OutlineNodeState child) =>
                  _OutlineNodeTile(node: child, depth: depth + 1),
            )
            .toList(growable: false),
      ),
    );
  }
}
