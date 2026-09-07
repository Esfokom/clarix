import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../../../core/editing/editor_bridge_types.dart';
import '../../application/workspace_providers.dart';
import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';
import 'package:clarix/src/features/ai/ai.dart';
import '../../domain/workspace_feature_state.dart';
import 'document_workspace.dart';
import 'quickstart_surface.dart';
import 'reader_inspector.dart';
import 'workspace_common.dart';

import 'package:clarix/src/core/theme_controller.dart';
import 'package:clarix/src/core/theme_profile.dart';

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
    final AiFeatureState aiState =
        ref.watch(aiNotifierProvider).value ?? AiFeatureState.initial();
    final bool isFullScreenStudy = widget.state.session.studyModeFullScreen;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showInspector = constraints.maxWidth >= 1200;
        final bool showAiInline =
            showInspector &&
            activeTab != null &&
            widget.state.session.rightToolWindow == RightToolWindow.ai;
        final bool showStudyModeInline =
            showInspector &&
            activeTab != null &&
            !isFullScreenStudy &&
            widget.state.session.rightToolWindow == RightToolWindow.studyMode;
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
                      child: (activeTab == null || isFullScreenStudy)
                          ? (widget.state.session.rightToolWindow == RightToolWindow.studyMode || isFullScreenStudy
                              ? _studyModePane(aiState, activeTab, isFullScreen: true)
                              : QuickstartSurface(state: widget.state))
                          : DocumentWorkspace(
                              state: widget.state,
                              activeTab: activeTab,
                            ),
                    ),
                  ),
                  if (showAiInline ||
                      showStudyModeInline ||
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
                          showStudyModeInline ||
                          showDocumentInline ||
                          showTextFormatInline) &&
                      !widget.state.session.rightPaneCollapsed)
                    SizedBox(
                      width: widget.state.session.rightPaneWidth,
                      child: showAiInline
                          ? _aiPane(aiState, activeTab)
                          : showStudyModeInline
                          ? _studyModePane(aiState, activeTab)
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

  Widget _aiPane(AiFeatureState aiState, DocumentTabState? tab) {
    if (tab != null) {
      final registry = ref.read(editorSessionRegistryProvider);
      if (registry[tab.id] == null) {
        unawaited(registry.open(tabId: tab.id, sourcePath: tab.filePath));
      }
    }
    final controller = tab == null
        ? null
        : ref.watch(agentRunControllerProvider(tab.id));
    final revision = tab == null
        ? 0
        : ref.watch(editorDocumentStateProvider(tab.id)).value?.revision ?? 0;
    return AiSidePane(
      aiState: aiState,
      documentContext: tab == null
          ? null
          : AiDocumentContext(
              tabId: tab.id,
              documentId: tab.documentId,
              title: tab.title,
              filePath: tab.filePath,
              editorRevision: revision,
              agentController: controller,
              isMissingFile: tab.isMissingFile,
            ),
      onCollapse: () =>
          ref.read(workspaceNotifierProvider.notifier).toggleComposerExpanded(),
    );
  }

  Widget _studyModePane(AiFeatureState aiState, DocumentTabState? tab, {bool isFullScreen = false}) {
    final context = tab == null
        ? const AiDocumentContext(
            tabId: 'study_mode_home',
            documentId: 'study_mode_home',
            title: 'Study Mode Workspace',
            filePath: 'study_mode_home',
            editorRevision: 0,
          )
        : AiDocumentContext(
            tabId: tab.id,
            documentId: tab.documentId,
            title: tab.title,
            filePath: tab.filePath,
            editorRevision: 0,
          );
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    return StudyModeSidePane(
      aiState: aiState,
      documentContext: context,
      colors: colors,
      isFullScreen: isFullScreen,
      onToggleFullScreen: () => ref
          .read(workspaceNotifierProvider.notifier)
          .setStudyModeFullScreen(!widget.state.session.studyModeFullScreen),
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
    final registry = ref.read(editorSessionRegistryProvider);
    if (registry[activeTab.id] == null) {
      unawaited(registry.open(tabId: activeTab.id, sourcePath: activeTab.filePath));
    }
    final native = ref.read(editorSessionRegistryProvider)[activeTab.id];
    if (native != null) {
      final catalog = ref.watch(installedFontCatalogProvider);
      return StreamBuilder<EditorDocumentState>(
        stream: native.changes,
        initialData: native.state,
        builder: (context, snapshot) {
          final document = snapshot.data ?? native.state;
          final selection = document.selection;
          EditorSceneObject? object;
          if (selection != null) {
            for (final scene in document.scenes.values) {
              object = scene.objects
                  .where(
                    (candidate) => candidate.objectId == selection.objectId,
                  )
                  .firstOrNull;
              if (object != null) break;
            }
          }
          if (selection == null || object == null) {
            for (final scene in document.scenes.values) {
              object = scene.objects
                  .where((candidate) => candidate.capability == 'editable')
                  .firstOrNull;
              if (object != null) break;
            }
          }
          if (object == null) {
            return _NoEditableTextSelection(tabId: activeTab.id);
          }
          final effectiveSelection = selection ??
              EditorSelection(
                objectId: object.objectId,
                range: const EditorTextRange(start: 0, end: 0),
              );
          return Column(
            children: [
              _MarkdownBridgeBanner(tabId: activeTab.id),
              Expanded(
                child: CanonicalPdfTextFormatPanel(
                  session: native,
                  object: object,
                  selection: effectiveSelection,
                  availableFamilies:
                      catalog.value?.families ??
                      <String>[?object.runs.firstOrNull?.style.fontFamily],
                ),
              ),
            ],
          );
        },
      );
    }
    return _NoEditableTextSelection(tabId: activeTab.id);
  }
}

class _MarkdownBridgeBanner extends ConsumerWidget {
  const _MarkdownBridgeBanner({required this.tabId});
  final String tabId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: WorkspaceColors.panel,
        border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(LucideIcons.type, size: 14, color: WorkspaceColors.accent),
              SizedBox(width: 6),
              Text(
                'Text & Markdown Studio',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: 'Open active PDF as editable Markdown document',
            child: ShadButton.outline(
              size: ShadButtonSize.sm,
              leading: const Icon(LucideIcons.fileEdit, size: 14),
              onPressed: () {
                ref.read(activeMarkdownEditorTabIdProvider.notifier).setTabId(tabId);
              },
              child: const Text('Open Markdown Document Editor', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoEditableTextSelection extends ConsumerWidget {
  const _NoEditableTextSelection({required this.tabId});
  final String tabId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: WorkspaceColors.panel,
      child: Column(
        children: [
          _MarkdownBridgeBanner(tabId: tabId),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WorkspaceColors.panelRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: WorkspaceColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(LucideIcons.mousePointerClick, size: 16, color: WorkspaceColors.accent),
                          SizedBox(width: 8),
                          Text(
                            'Text Format Studio',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Click any text on the PDF canvas to edit in-place, or launch the full Document Editor below to format the document using Word Processor Ribbons.',
                        style: TextStyle(fontSize: 11, color: WorkspaceColors.textMuted),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ShadButton(
                          size: ShadButtonSize.sm,
                          leading: const Icon(LucideIcons.fileEdit, size: 14),
                          onPressed: () {
                            ref.read(activeMarkdownEditorTabIdProvider.notifier).setTabId(tabId);
                          },
                          child: const Text('Open Full Document Ribbon Editor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Group 1: Typography Presets
                const Text('TYPOGRAPHY PRESETS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: WorkspaceColors.textMuted, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _presetChip(context, 'Title (28pt)', () => _openMarkdownWithSnippet(ref, '# Document Title\n')),
                    _presetChip(context, 'Heading 1 (24pt)', () => _openMarkdownWithSnippet(ref, '# Section Heading\n')),
                    _presetChip(context, 'Heading 2 (18pt)', () => _openMarkdownWithSnippet(ref, '## Sub-Section\n')),
                    _presetChip(context, 'Heading 3 (14pt)', () => _openMarkdownWithSnippet(ref, '### Detail Heading\n')),
                    _presetChip(context, 'Blockquote', () => _openMarkdownWithSnippet(ref, '> Callout Quote\n')),
                    _presetChip(context, 'Code Block', () => _openMarkdownWithSnippet(ref, '```dart\n// Code snippet\n```\n')),
                  ],
                ),
                const SizedBox(height: 14),

                // Group 2: Insert Elements
                const Text('INSERT ELEMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: WorkspaceColors.textMuted, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _toolChip(context, LucideIcons.table, 'Table', () => _openMarkdownWithSnippet(ref, '| Col 1 | Col 2 |\n| --- | --- |\n| Val 1 | Val 2 |\n')),
                    _toolChip(context, LucideIcons.image, 'Image', () => _openMarkdownWithSnippet(ref, '![Image](path_to_image)\n')),
                    _toolChip(context, LucideIcons.link, 'Hyperlink', () => _openMarkdownWithSnippet(ref, '[Link Text](https://example.com)')),
                    _toolChip(context, LucideIcons.minus, 'Divider', () => _openMarkdownWithSnippet(ref, '\n---\n')),
                    _toolChip(context, LucideIcons.sigma, 'Math Formula', () => _openMarkdownWithSnippet(ref, '\$\$\nE = mc^2\n\$\$\n')),
                  ],
                ),
                const SizedBox(height: 14),

                // Group 3: Page Setup & Layout Presets
                const Text('PAGE LAYOUT & FORMAT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: WorkspaceColors.textMuted, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: WorkspaceColors.panelRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: WorkspaceColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('Page Size:', style: TextStyle(fontSize: 11, color: WorkspaceColors.textMuted)),
                          Text('A4 (210 x 297 mm)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('Orientation:', style: TextStyle(fontSize: 11, color: WorkspaceColors.textMuted)),
                          Text('Portrait', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('Line Height:', style: TextStyle(fontSize: 11, color: WorkspaceColors.textMuted)),
                          Text('1.5x Spacing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openMarkdownWithSnippet(WidgetRef ref, String snippet) {
    ref.read(activeMarkdownEditorTabIdProvider.notifier).setTabId(tabId);
  }

  Widget _presetChip(BuildContext context, String label, VoidCallback onTap) {
    return ActionChip(
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      backgroundColor: WorkspaceColors.panelRaised,
      side: const BorderSide(color: WorkspaceColors.border),
      label: Text(label, style: const TextStyle(fontSize: 11, color: WorkspaceColors.textStrong)),
      onPressed: onTap,
    );
  }

  Widget _toolChip(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 12, color: WorkspaceColors.accent),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      backgroundColor: WorkspaceColors.panelRaised,
      side: const BorderSide(color: WorkspaceColors.border),
      label: Text(label, style: const TextStyle(fontSize: 11, color: WorkspaceColors.textStrong)),
      onPressed: onTap,
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
          Tooltip(
            message: 'Study Mode',
            child: ShadIconButton.ghost(
              key: const Key('right-tool-studyMode'),
              width: 40,
              height: 40,
              padding: EdgeInsets.zero,
              backgroundColor: state.session.rightToolWindow == RightToolWindow.studyMode
                  ? WorkspaceColors.accentSoft
                  : null,
              icon: const QaMergedIcon(size: 16),
              onPressed: () => ref
                  .read(workspaceNotifierProvider.notifier)
                  .selectRightToolWindow(RightToolWindow.studyMode),
            ),
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
