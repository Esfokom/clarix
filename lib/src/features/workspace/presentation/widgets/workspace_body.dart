import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'ai_side_pane.dart';
import 'document_workspace.dart';
import 'model_catalog_sheet.dart';
import 'quickstart_surface.dart';
import 'workspace_common.dart';
import 'workspace_sidebar.dart';

class WorkspaceBody extends ConsumerWidget {
  const WorkspaceBody({required this.state, super.key});

  final WorkspaceFeatureState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DocumentTabState? activeTab = _activeTab(state);
    final bool hasTabs = activeTab != null;
    final bool showAiPane = hasTabs && state.composerExpanded;

    return Stack(
      children: <Widget>[
        SafeArea(
          child: Row(
            children: <Widget>[
              WorkspaceSidebar(state: state, activeTab: activeTab),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: WorkspaceColors.border),
                      right: BorderSide(color: WorkspaceColors.border),
                    ),
                  ),
                  child: hasTabs
                      ? DocumentWorkspace(
                          state: state,
                          activeTab: activeTab,
                        )
                      : QuickstartSurface(state: state),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: showAiPane ? 356 : 0,
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: WorkspaceColors.border)),
                ),
                child: showAiPane
                    ? AiSidePane(state: state, activeTab: activeTab)
                    : null,
              ),
            ],
          ),
        ),
        if (hasTabs && !state.composerExpanded)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => ref
                    .read(workspaceNotifierProvider.notifier)
                    .toggleComposerExpanded(),
                child: Container(
                  width: 18,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: WorkspaceColors.panelRaised,
                    border: Border(
                      left: BorderSide(color: WorkspaceColors.border),
                      top: BorderSide(color: WorkspaceColors.border),
                      bottom: BorderSide(color: WorkspaceColors.border),
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.chevronLeft,
                    size: 14,
                    color: WorkspaceColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        if (state.showModelCatalog) ...<Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => ref
                  .read(workspaceNotifierProvider.notifier)
                  .toggleModelCatalog(false),
              child: Container(color: WorkspaceColors.backdrop),
            ),
          ),
          const Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(width: 388, child: ModelCatalogSheet()),
          ),
        ],
      ],
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
