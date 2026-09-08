import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import '../../application/workspace_providers.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:clarix/src/features/study/study.dart';
import '../../domain/workspace_feature_state.dart';
import 'document_workspace.dart';
import 'quickstart_surface.dart';
import 'reader_inspector.dart';
import 'workspace_common.dart';
import 'package:clarix/src/features/reader/presentation/reader_viewer_pane.dart';

class WorkspaceBody extends ConsumerStatefulWidget {
  const WorkspaceBody({
    required this.state,
    required this.onOpenSettings,
    this.fullscreenReader = false,
    this.onExitFullscreen,
    super.key,
  });

  final WorkspaceFeatureState state;
  final VoidCallback onOpenSettings;
  final bool fullscreenReader;
  final VoidCallback? onExitFullscreen;

  @override
  ConsumerState<WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends ConsumerState<WorkspaceBody> {
  @override
  Widget build(BuildContext context) {
    final DocumentTabState? activeTab = _activeTab(widget.state);
    final AiFeatureState aiState =
        ref.watch(aiNotifierProvider).value ?? AiFeatureState.initial();
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    if (widget.fullscreenReader && activeTab != null) {
      return _FullscreenReader(
        tab: activeTab,
        state: widget.state,
        onExit: widget.onExitFullscreen!,
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showInspector = constraints.maxWidth >= 1200;
        final bool showAiInline =
            showInspector &&
            activeTab != null &&
            widget.state.session.rightToolWindow == RightToolWindow.ai;
        final bool showDocumentInline =
            showInspector &&
            activeTab != null &&
            widget.state.session.rightToolWindow == RightToolWindow.document;
        final bool showStudyInline =
            showInspector &&
            activeTab != null &&
            widget.state.session.rightToolWindow == RightToolWindow.study;
        final bool showAnyInline =
            showAiInline || showDocumentInline || showStudyInline;
        final bool showAiOverlay =
            !showInspector &&
            activeTab != null &&
            widget.state.composerExpanded;

        return Stack(
          children: <Widget>[
            SafeArea(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide.none,
                          right: showInspector && activeTab != null
                              ? BorderSide(color: colors.border)
                              : BorderSide.none,
                        ),
                      ),
                      child: activeTab == null
                          ? QuickstartSurface(state: widget.state)
                          : DocumentWorkspace(
                              state: widget.state,
                              activeTab: activeTab,
                            ),
                    ),
                  ),
                  if (showAnyInline)
                    _PaneHandle(
                      key: const Key('right-pane-resizer'),
                      colors: colors,
                      onDrag: (double delta) => ref
                          .read(workspaceNotifierProvider.notifier)
                          .setRightPaneWidth(
                            widget.state.session.rightPaneWidth - delta,
                          ),
                    ),
                  if (showAnyInline && !widget.state.session.rightPaneCollapsed)
                    SizedBox(
                      width: widget.state.session.rightPaneWidth,
                      child: showAiInline
                          ? _aiPane(aiState, activeTab)
                          : showStudyInline
                          ? _studyPane(activeTab)
                          : ReaderInspector(
                              state: widget.state,
                              activeTab: activeTab,
                            ),
                    ),
                  if (showInspector && activeTab != null)
                    _RightToolRail(state: widget.state, colors: colors),
                ],
              ),
            ),
            if (showAiOverlay) ...<Widget>[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .toggleComposerExpanded(),
                  child: Container(color: colors.backdrop),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: constraints.maxWidth.clamp(320, 380).toDouble(),
                  child: _aiPane(aiState, activeTab),
                ),
              ),
            ],
            if (widget.state.bannerMessage != null)
              Positioned(
                left: 24,
                right: 24,
                top: 16,
                child: Center(
                  child: SurfaceBlock(
                    colors: colors,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (widget.state.pdfSaveInProgress)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            widget.state.bannerMessage!,
                            style: TextStyle(
                              color: colors.warning,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _aiPane(AiFeatureState aiState, DocumentTabState? tab) {
    return AiSidePane(
      aiState: aiState,
      documentContext: tab == null
          ? null
          : AiDocumentContext(
              tabId: tab.id,
              documentId: tab.documentId,
              title: tab.title,
              filePath: tab.filePath,
              isMissingFile: tab.isMissingFile,
            ),
      onCollapse: () =>
          ref.read(workspaceNotifierProvider.notifier).toggleComposerExpanded(),
    );
  }

  Widget _studyPane(DocumentTabState tab) {
    return StudySidePane(
      documentId: tab.documentId,
      onCollapse: () => ref
          .read(workspaceNotifierProvider.notifier)
          .selectRightToolWindow(RightToolWindow.study),
      onNavigateToPage: (int pageNumber) => ref
          .read(workspaceNotifierProvider.notifier)
          .updateViewerState(tabId: tab.id, currentPage: pageNumber),
    );
  }

  DocumentTabState? _activeTab(WorkspaceFeatureState state) {
    final String? activeId = state.session.activeTabId;
    if (activeId == null) {
      return null;
    }
    for (final DocumentTabState tab in state.session.tabs) {
      if (tab.id == activeId) {
        return tab;
      }
    }
    return null;
  }
}

class _FullscreenReader extends ConsumerStatefulWidget {
  const _FullscreenReader({
    required this.tab,
    required this.state,
    required this.onExit,
  });
  final DocumentTabState tab;
  final WorkspaceFeatureState state;
  final VoidCallback onExit;
  @override
  ConsumerState<_FullscreenReader> createState() => _FullscreenReaderState();
}

class _FullscreenReaderState extends ConsumerState<_FullscreenReader> {
  bool _showExit = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onHover: (_) {
      if (!_showExit) setState(() => _showExit = true);
    },
    child: Stack(
      children: <Widget>[
        Positioned.fill(
          child: ReaderViewerPane(
            tab: widget.tab,
            documentRef: ref.watch(pdfDocumentRefProvider(widget.tab.filePath)),
            annotations:
                widget
                    .state
                    .documentMetadata[widget.tab.documentId]
                    ?.annotations ??
                const <DocumentAnnotation>[],
            colors: WorkspaceSurfaceTokens.fromProfile(
              ref.watch(clarixThemeProvider).value ??
                  const ClarixThemeProfile(),
              context,
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_showExit,
            child: AnimatedOpacity(
              opacity: _showExit ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Center(
                child: Tooltip(
                  message: 'Exit fullscreen (Escape)',
                  child: IconButton.filled(
                    key: const Key('fullscreen-reader-exit'),
                    onPressed: widget.onExit,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PaneHandle extends StatelessWidget {
  const _PaneHandle({super.key, required this.onDrag, required this.colors});
  final ValueChanged<double> onDrag;
  final WorkspaceSurfaceTokens colors;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 6,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (DragUpdateDetails details) =>
          onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Center(
          child: Container(
            width: 2,
            height: 36,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RightToolRail extends ConsumerWidget {
  const _RightToolRail({required this.state, required this.colors});
  final WorkspaceFeatureState state;
  final WorkspaceSurfaceTokens colors;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 40,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: <Widget>[
          _tool(
            context,
            ref,
            RightToolWindow.document,
            'Document inspector',
            LucideIcons.panelRight,
          ),
          _tool(
            context,
            ref,
            RightToolWindow.ai,
            'Clarix AI',
            LucideIcons.sparkles,
          ),
          _tool(
            context,
            ref,
            RightToolWindow.study,
            'Study',
            LucideIcons.graduationCap,
          ),
        ],
      ),
    ),
  );
  Widget _tool(
    BuildContext context,
    WidgetRef ref,
    RightToolWindow tool,
    String label,
    IconData icon,
  ) => Tooltip(
    message: label,
    child: ShadIconButton.ghost(
      key: Key('right-tool-${tool.name}'),
      width: 40,
      height: 40,
      padding: EdgeInsets.zero,
      backgroundColor: state.session.rightToolWindow == tool
          ? colors.accentSoft
          : null,
      icon: Icon(icon, size: 16),
      onPressed: () => ref
          .read(workspaceNotifierProvider.notifier)
          .selectRightToolWindow(tool),
    ),
  );
}
