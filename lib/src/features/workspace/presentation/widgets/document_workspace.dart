import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../../../../core/models.dart';
import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import '../../../../core/workspace_surface_tokens.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'package:clarix/src/features/reader/presentation/reader_viewer_pane.dart';

class DocumentWorkspace extends ConsumerWidget {
  const DocumentWorkspace({
    required this.state,
    required this.activeTab,
    super.key,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    final nativeState = ref
        .watch(editorDocumentStateProvider(activeTab.id))
        .value;
    final nativeController = ref.read(
      editorSessionRegistryProvider,
    )[activeTab.id];
    return Column(
      children: <Widget>[
        _TabStrip(state: state, activeTab: activeTab, colors: colors),
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: ReaderViewerPane(
                  tab: activeTab,
                  documentRef: ref.watch(
                    pdfDocumentRefProvider(activeTab.filePath),
                  ),
                  annotations:
                      state
                          .documentMetadata[activeTab.documentId]
                          ?.annotations ??
                      const <DocumentAnnotation>[],
                  colors: colors,
                ),
              ),
              if (nativeState?.recoveredRevision case final revision?)
                Align(
                  alignment: Alignment.topCenter,
                  child: RecoveryBanner(
                    revision: revision,
                    onReview: nativeController?.dismissRecovery ?? () {},
                    onDismiss: nativeController?.dismissRecovery ?? () {},
                  ),
                ),
              if (nativeState?.save.phase == EditorSavePhase.saving)
                Center(
                  child: SaveProgressDialog(
                    stage: nativeState?.save.stage ?? 'FlushCommands',
                    onCancel:
                        nativeState?.save.stage == 'CommitComposition' ||
                            nativeState?.save.stage == 'FlushCommands'
                        ? nativeController?.cancelSave
                        : null,
                  ),
                ),
              if (nativeState?.save.phase == EditorSavePhase.failed)
                Center(
                  child: SaveConflictDialog(
                    errorCode:
                        nativeState?.save.errorCode ?? 'editor_save_failed',
                    onRetry: () => unawaited(
                      ref
                          .read(workspaceNotifierProvider.notifier)
                          .saveActivePdfEdits(),
                    ),
                    onSaveAs: () => unawaited(() async {
                      final followCopy = await showSaveAsAssociationDialog(
                        context,
                      );
                      if (followCopy == null) return;
                      await ref
                          .read(workspaceNotifierProvider.notifier)
                          .saveActivePdfEditsAsCopy(
                            association: followCopy
                                ? EditorSaveAssociation.followNewSource
                                : EditorSaveAssociation.keepOriginalAssociation,
                          );
                    }()),
                    onRebase: () => unawaited(
                      ref
                          .read(workspaceNotifierProvider.notifier)
                          .rebaseActiveNativeEditor(),
                    ),
                    onCancel: nativeController?.dismissSaveFailure ?? () {},
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends ConsumerStatefulWidget {
  const _TabStrip({
    required this.state,
    required this.activeTab,
    required this.colors,
  });

  final WorkspaceFeatureState state;
  final DocumentTabState activeTab;
  final WorkspaceSurfaceTokens colors;

  @override
  ConsumerState<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<_TabStrip> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 760;
        return Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.colors.canvasRaised,
            border: Border(bottom: BorderSide(color: widget.colors.border)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.state.session.tabs.length,
                  separatorBuilder: (_, int index) => const SizedBox(width: 4),
                  itemBuilder: (BuildContext context, int index) {
                    final DocumentTabState tab =
                        widget.state.session.tabs[index];
                    final bool selected = tab.id == widget.activeTab.id;
                    return GestureDetector(
                      onTap: () => ref
                          .read(workspaceNotifierProvider.notifier)
                          .setActiveTab(tab.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? widget.colors.panelRaised
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: selected
                                ? widget.colors.accentBorder
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              tab.isMissingFile
                                  ? LucideIcons.triangleAlert
                                  : LucideIcons.fileText,
                              size: 13,
                              color: tab.isMissingFile
                                  ? widget.colors.warning
                                  : widget.colors.textMuted,
                            ),
                            const SizedBox(width: 7),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? 96 : 160,
                              ),
                              child: Text(
                                tab.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: widget.colors.textStrong,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _confirmCloseTab(tab),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  LucideIcons.x,
                                  size: 12,
                                  color: widget.colors.textFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              _IndexStatusIndicator(status: widget.activeTab.indexStatus),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmCloseTab(DocumentTabState tab) async {
    final notifier = ref.read(workspaceNotifierProvider.notifier);
    final native = ref.read(editorSessionRegistryProvider)[tab.id];
    if (native != null && notifier.hasUnsavedEditsFor(tab.id)) {
      final choice = await showDirtyCloseDialog(context);
      if (choice != null) {
        await notifier.closeTab(tab.id, nativeDirtyChoice: choice);
      }
      return;
    }
    if (!notifier.hasUnsavedEditsFor(tab.id)) {
      await notifier.closeTab(tab.id);
      return;
    }
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: WorkspaceColors.panel,
        title: const Text(
          'Save PDF edits?',
          style: TextStyle(color: WorkspaceColors.textStrong),
        ),
        content: Text(
          '“${tab.title}” has unsaved bookmarks or highlights.',
          style: const TextStyle(color: WorkspaceColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await notifier.setActiveTab(tab.id);
      await notifier.saveActivePdfEdits();
      if (notifier.hasUnsavedEditsFor(tab.id)) return;
    }
    if (choice == 'save' || choice == 'discard') {
      await notifier.closeTab(tab.id);
    }
  }
}

class _IndexStatusIndicator extends StatefulWidget {
  const _IndexStatusIndicator({required this.status});
  final DocumentIndexStatus status;
  @override
  State<_IndexStatusIndicator> createState() => _IndexStatusIndicatorState();
}

class _IndexStatusIndicatorState extends State<_IndexStatusIndicator>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool active =
        widget.status == DocumentIndexStatus.queued ||
        widget.status == DocumentIndexStatus.indexing;
    final Color color = widget.status == DocumentIndexStatus.indexed
        ? const Color(0xFF5BA56A)
        : active
        ? const Color(0xFFC5C5C5)
        : WorkspaceColors.textFaint;
    final String message = switch (widget.status) {
      DocumentIndexStatus.indexed =>
        'Indexed — ready for document-aware AI answers.',
      DocumentIndexStatus.indexing =>
        'Indexing this PDF for document-aware AI answers.',
      DocumentIndexStatus.queued => 'PDF indexing is queued.',
      DocumentIndexStatus.failed =>
        'Indexing failed. AI may use limited document context.',
      DocumentIndexStatus.unavailable =>
        'Indexing is unavailable for this document.',
      DocumentIndexStatus.idle => 'PDF has not been indexed yet.',
    };
    return Tooltip(
      message: message,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: active
            ? FadeTransition(
                opacity: Tween<double>(
                  begin: .35,
                  end: 1,
                ).animate(_controller!),
                child: _dot(color),
              )
            : _dot(color),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
