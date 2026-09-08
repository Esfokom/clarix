import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'workspace_common.dart';

class ReaderInspector extends ConsumerWidget {
  const ReaderInspector({
    required this.state,
    required this.activeTab,
    super.key,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DocumentMetadata? metadata =
        state.documentMetadata[activeTab.documentId];
    final List<DocumentBookmark> bookmarks =
        metadata?.bookmarks ?? const <DocumentBookmark>[];
    final List<DocumentAnnotation> annotations =
        metadata?.annotations ?? const <DocumentAnnotation>[];
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.panel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Document',
                    style: TextStyle(
                      color: colors.textStrong,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Open local AI assistant',
                  child: ShadIconButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    icon: const Icon(LucideIcons.sparkles, size: 15),
                    onPressed: () => ref
                        .read(workspaceNotifierProvider.notifier)
                        .toggleComposerExpanded(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: <Widget>[
                Text(
                  activeTab.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${activeTab.pageCountHint ?? '—'} pages · local file',
                  style: TextStyle(color: colors.textFaint, fontSize: 10.5),
                ),
                const SizedBox(height: 18),
                SectionLabel(label: 'Bookmarks', colors: colors),
                if (bookmarks.isEmpty)
                  SidebarEmpty(message: 'No bookmarks yet', colors: colors)
                else
                  for (final DocumentBookmark bookmark in bookmarks)
                    _InspectorItem(
                      icon: LucideIcons.bookmark,
                      title: bookmark.label,
                      subtitle: 'Page ${bookmark.pageNumber}',
                      colors: colors,
                      onTap: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .updateViewerState(
                            tabId: activeTab.id,
                            currentPage: bookmark.pageNumber,
                          ),
                    ),
                const SizedBox(height: 18),
                SectionLabel(label: 'Notes', colors: colors),
                if (annotations.isEmpty)
                  SidebarEmpty(message: 'No annotations yet', colors: colors)
                else
                  for (final DocumentAnnotation annotation in annotations)
                    _InspectorItem(
                      icon: annotation.kind == AnnotationKind.highlight
                          ? LucideIcons.highlighter
                          : LucideIcons.stickyNote,
                      title: annotation.note?.isNotEmpty == true
                          ? annotation.note!
                          : annotation.selectedText,
                      subtitle: 'Page ${annotation.pageNumber}',
                      colors: colors,
                      onTap: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .updateViewerState(
                            tabId: activeTab.id,
                            currentPage: annotation.pageNumber,
                          ),
                      onEdit: annotation.kind == AnnotationKind.note
                          ? () => _showEditNote(context, ref, annotation)
                          : null,
                      onDelete: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .removeAnnotation(activeTab.id, annotation.id),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditNote(
    BuildContext context,
    WidgetRef ref,
    DocumentAnnotation annotation,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: annotation.note,
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Edit note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Note'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) {
      return;
    }
    await ref
        .read(workspaceNotifierProvider.notifier)
        .updateAnnotationNote(
          tabId: activeTab.id,
          annotationId: annotation.id,
          note: value,
        );
  }
}

class _InspectorItem extends StatelessWidget {
  const _InspectorItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.colors,
    this.onEdit,
    this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.panelRaised,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 14, color: colors.textMuted),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textStrong,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.textFaint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit note',
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    color: colors.textFaint,
                    onPressed: onEdit,
                    icon: const Icon(LucideIcons.pencilLine),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Delete annotation',
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    color: colors.textFaint,
                    onPressed: onDelete,
                    icon: const Icon(LucideIcons.trash2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
