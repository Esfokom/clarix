import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'ai_side_pane.dart';
import 'document_workspace.dart';
import 'quickstart_surface.dart';
import 'reader_inspector.dart';
import 'workspace_common.dart';
import 'workspace_sidebar.dart';

class WorkspaceBody extends ConsumerStatefulWidget {
  const WorkspaceBody({
    required this.state,
    required this.onOpenSettings,
    super.key,
  });

  final WorkspaceFeatureState state;
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends ConsumerState<WorkspaceBody> {
  bool _mobileNavigationOpen = false;

  @override
  Widget build(BuildContext context) {
    final DocumentTabState? activeTab = _activeTab(widget.state);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showNavigation = constraints.maxWidth >= 900;
        final bool showInspector = constraints.maxWidth >= 1200;
        final bool showAiInline =
            showInspector && activeTab != null && widget.state.composerExpanded;
        final bool showAiOverlay =
            !showInspector &&
            activeTab != null &&
            widget.state.composerExpanded;

        return Stack(
          children: <Widget>[
            SafeArea(
              child: Row(
                children: <Widget>[
                  if (showNavigation && !widget.state.session.leftPaneCollapsed)
                    SizedBox(
                      width: widget.state.session.leftPaneWidth,
                      child: WorkspaceSidebar(
                        state: widget.state,
                        activeTab: activeTab,
                        onOpenSettings: widget.onOpenSettings,
                      ),
                    ),
                  if (showNavigation)
                    _PaneHandle(
                      key: const Key('left-pane-resizer'),
                      onDrag: (double delta) => ref
                          .read(workspaceNotifierProvider.notifier)
                          .setLeftPaneWidth(
                            widget.state.session.leftPaneWidth + delta,
                          ),
                    ),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: showNavigation
                              ? const BorderSide(color: WorkspaceColors.border)
                              : BorderSide.none,
                          right: showInspector && activeTab != null
                              ? const BorderSide(color: WorkspaceColors.border)
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
                  if (showInspector && activeTab != null)
                    _PaneHandle(
                      key: const Key('right-pane-resizer'),
                      onDrag: (double delta) => ref
                          .read(workspaceNotifierProvider.notifier)
                          .setRightPaneWidth(
                            widget.state.session.rightPaneWidth - delta,
                          ),
                    ),
                  if (showInspector &&
                      activeTab != null &&
                      !widget.state.session.rightPaneCollapsed)
                    SizedBox(
                      width: widget.state.session.rightPaneWidth,
                      child: showAiInline
                          ? AiSidePane(
                              state: widget.state,
                              activeTab: activeTab,
                            )
                          : ReaderInspector(
                              state: widget.state,
                              activeTab: activeTab,
                            ),
                    ),
                ],
              ),
            ),
            if (!showNavigation && !_mobileNavigationOpen)
              Positioned(
                left: 8,
                top: 10,
                child: Tooltip(
                  message: 'Open document navigation',
                  child: ShadIconButton.ghost(
                    width: 32,
                    height: 32,
                    padding: EdgeInsets.zero,
                    icon: const Icon(LucideIcons.panelLeftOpen, size: 16),
                    onPressed: () =>
                        setState(() => _mobileNavigationOpen = true),
                  ),
                ),
              ),
            if (!showNavigation && _mobileNavigationOpen) ...<Widget>[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _mobileNavigationOpen = false),
                  child: Container(color: WorkspaceColors.backdrop),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: constraints.maxWidth.clamp(240, 300).toDouble(),
                  child: WorkspaceSidebar(
                    state: widget.state,
                    activeTab: activeTab,
                    onOpenSettings: widget.onOpenSettings,
                  ),
                ),
              ),
            ],
            if (showAiOverlay) ...<Widget>[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .toggleComposerExpanded(),
                  child: Container(color: WorkspaceColors.backdrop),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: constraints.maxWidth.clamp(320, 380).toDouble(),
                  child: AiSidePane(state: widget.state, activeTab: activeTab),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      widget.state.bannerMessage!,
                      style: const TextStyle(
                        color: WorkspaceColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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

class _PaneHandle extends StatelessWidget {
  const _PaneHandle({super.key, required this.onDrag});
  final ValueChanged<double> onDrag;
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
              color: WorkspaceColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}
