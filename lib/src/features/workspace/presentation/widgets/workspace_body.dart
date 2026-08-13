import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import '../../domain/pdf_edit_intent.dart';
import '../../domain/pdf_text_types.dart';
import '../../infrastructure/installed_font_catalog.dart';
import 'ai_side_pane.dart';
import 'document_workspace.dart';
import 'quickstart_surface.dart';
import 'pdf_text_format_panel.dart';
import 'reader_inspector.dart';
import 'workspace_common.dart';

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
  @override
  Widget build(BuildContext context) {
    final DocumentTabState? activeTab = _activeTab(widget.state);
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
        final bool showTextFormatInline =
            showInspector &&
            activeTab != null &&
            widget.state.session.rightToolWindow == RightToolWindow.textFormat;
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
                  if (showAiInline ||
                      showDocumentInline ||
                      showTextFormatInline)
                    _PaneHandle(
                      key: const Key('right-pane-resizer'),
                      onDrag: (double delta) => ref
                          .read(workspaceNotifierProvider.notifier)
                          .setRightPaneWidth(
                            widget.state.session.rightPaneWidth - delta,
                          ),
                    ),
                  if ((showAiInline ||
                          showDocumentInline ||
                          showTextFormatInline) &&
                      !widget.state.session.rightPaneCollapsed)
                    SizedBox(
                      width: widget.state.session.rightPaneWidth,
                      child: showAiInline
                          ? AiSidePane(
                              state: widget.state,
                              activeTab: activeTab,
                            )
                          : showTextFormatInline
                          ? _TextFormatPane(activeTab: activeTab)
                          : ReaderInspector(
                              state: widget.state,
                              activeTab: activeTab,
                            ),
                    ),
                  if (showInspector && activeTab != null)
                    _RightToolRail(state: widget.state),
                ],
              ),
            ),
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
                            style: const TextStyle(
                              color: WorkspaceColors.warning,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        for (final action
                            in widget.state.pdfFailure?.actions ??
                                const <PdfRecoveryAction>[])
                          TextButton(
                            key: Key('pdf-recovery-${action.name}'),
                            onPressed: () => ref
                                .read(workspaceNotifierProvider.notifier)
                                .recoverPdfFailure(action),
                            child: Text(_recoveryLabel(action)),
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

String _recoveryLabel(PdfRecoveryAction action) => switch (action) {
  PdfRecoveryAction.reload => 'Reload',
  PdfRecoveryAction.saveCopy => 'Save a Copy',
  PdfRecoveryAction.selectBlock => 'Show block',
  PdfRecoveryAction.rediscover => 'Rediscover',
};

class _TextFormatPane extends ConsumerWidget {
  const _TextFormatPane({required this.activeTab});

  final DocumentTabState activeTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(pdfEditingControllerProvider);
    final session = editing.sessionsByTabId[activeTab.id];
    final selection = session?.selection;
    PdfTextBlock? block;
    if (selection != null && session != null) {
      for (final candidate in session.blocks) {
        if (candidate.locator == selection.locator) {
          block = candidate;
          break;
        }
      }
    }
    if (session == null || selection == null || block == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Select editable PDF text to format it.'),
        ),
      );
    }
    final catalog = ref.watch(installedFontCatalogProvider);
    final families =
        catalog.value?.families ??
        <String>{...block.runs.map((run) => run.style.fontFamily)}.toList();
    String? substitutionMessage;
    final installed = catalog.value;
    if (installed != null && block.text.isNotEmpty) {
      final style = block.styleAt(
        selection.range.start.clamp(0, block.text.length),
      );
      try {
        final match = installed.match(
          FontMatchRequest(
            family: style.fontFamily,
            weight: style.fontWeight,
            italic: style.italic,
            text: block.text,
          ),
        );
        if (match.requiresSubstitution) {
          substitutionMessage =
              '${style.fontFamily} is not installed. Save will embed the closest compatible face: ${match.font.family} ${match.font.face}.';
        }
      } on FontMatchUnavailable catch (error) {
        substitutionMessage = error.message;
      }
    }
    return PdfTextFormatPanel(
      documentId: session.documentId,
      documentRevision: session.revision,
      block: block,
      selection: selection,
      availableFamilies: families,
      caseMatching: session.caseMatching,
      substitutionMessage: substitutionMessage,
      onCaseMatchingChanged: (enabled) => editing.dispatch(
        SetPdfCaseMatchingIntent(
          documentId: session.documentId,
          documentRevision: session.revision,
          enabled: enabled,
        ),
        provenance: PdfCommandProvenance.manual,
      ),
      onIntent: (intent) =>
          editing.dispatch(intent, provenance: PdfCommandProvenance.manual),
    );
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

class _RightToolRail extends ConsumerWidget {
  const _RightToolRail({required this.state});
  final WorkspaceFeatureState state;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 40,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: WorkspaceColors.panel,
        border: Border(left: BorderSide(color: WorkspaceColors.border)),
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
            RightToolWindow.textFormat,
            'Text format',
            LucideIcons.type,
          ),
          _tool(
            context,
            ref,
            RightToolWindow.ai,
            'Clarix AI',
            LucideIcons.sparkles,
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
          ? WorkspaceColors.accentSoft
          : null,
      icon: Icon(icon, size: 16),
      onPressed: () => ref
          .read(workspaceNotifierProvider.notifier)
          .selectRightToolWindow(tool),
    ),
  );
}
