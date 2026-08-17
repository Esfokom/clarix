import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:clarix/src/features/ai/ai.dart';
import '../../../core/theme_controller.dart';
import '../../../core/theme_profile.dart';
import '../../../core/workspace_surface_tokens.dart';

class AiSidePane extends ConsumerStatefulWidget {
  const AiSidePane({
    required this.aiState,
    required this.documentContext,
    required this.onCollapse,
    super.key,
  });

  final AiFeatureState aiState;
  final AiDocumentContext? documentContext;
  final VoidCallback onCollapse;

  @override
  ConsumerState<AiSidePane> createState() => _AiSidePaneState();
}

class _AiSidePaneState extends ConsumerState<AiSidePane> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    final AiWorkspaceState ai = widget.aiState.chat;
    final agentController = widget.documentContext?.agentController;
    final editorRevision = widget.documentContext?.editorRevision ?? 0;
    final int contextLimit =
        widget.aiState.providerProfiles
            .where((profile) => profile.id == ai.selectedProviderId)
            .firstOrNull
            ?.contextWindowTokens ??
        256000;
    final int estimatedTokens = ai.messages.fold<int>(
      0,
      (int total, ComposerMessage message) =>
          total + (message.text.trim().length / 4).ceil(),
    );
    final int contextPercent = ((estimatedTokens / contextLimit) * 100)
        .clamp(0, 100)
        .round();

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.panel),
      child: Column(
        children: <Widget>[
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Clarix AI',
                    style: TextStyle(
                      color: colors.textStrong,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Conversation history',
                  child: ShadIconButton.ghost(
                    key: const Key('ai-conversation-history'),
                    width: 28,
                    height: 28,
                    padding: EdgeInsets.zero,
                    icon: const Icon(LucideIcons.history, size: 14),
                    onPressed: ai.chatBusy || widget.documentContext == null
                        ? null
                        : _showHistory,
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message:
                      'Estimated conversation context: $estimatedTokens of $contextLimit tokens',
                  child: Text(
                    '$contextPercent%',
                    key: const Key('ai-context-usage'),
                    style: TextStyle(
                      color: colors.textFaint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'New conversation',
                  child: ShadIconButton.ghost(
                    key: const Key('ai-new-conversation'),
                    width: 28,
                    height: 28,
                    padding: EdgeInsets.zero,
                    icon: const Icon(LucideIcons.squarePen, size: 14),
                    onPressed: ai.chatBusy
                        ? null
                        : () => ref
                              .read(aiNotifierProvider.notifier)
                              .startNewConversation(),
                  ),
                ),
                const SizedBox(width: 4),
                ShadIconButton.ghost(
                  width: 28,
                  height: 28,
                  padding: EdgeInsets.zero,
                  icon: const Icon(LucideIcons.chevronRight, size: 14),
                  onPressed: widget.onCollapse,
                ),
              ],
            ),
          ),
          if (agentController != null)
            StreamBuilder<AgentRunControllerState>(
              stream: agentController.changes,
              initialData: agentController.state,
              builder: (context, snapshot) => _AgentRunPanel(
                state: snapshot.data ?? agentController.state,
                currentRevision: editorRevision,
                controller: agentController,
              ),
            ),
          Expanded(
            child: ai.messages.isEmpty
                ? _EmptyConversation(
                    providerReady: ai.providerReady,
                    colors: colors,
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: ai.messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ComposerMessage message =
                          ai.messages[ai.messages.length - 1 - index];
                      return _MessageBubble(
                        message: message,
                        documentContext: widget.documentContext,
                        colors: colors,
                      );
                    },
                  ),
          ),
          if (ai.chatBusy) _ComposerLoadingIndicator(colors: colors),
          _DocumentComposer(
            controller: _controller,
            enabled: ai.providerReady && !ai.chatBusy,
            isBusy: ai.chatBusy,
            onSend: _send,
            colors: colors,
            onStop: () =>
                ref.read(aiNotifierProvider.notifier).stopGeneration(),
          ),
        ],
      ),
    );
  }

  void _send() {
    final String prompt = _controller.text.trim();
    if (prompt.isEmpty) {
      return;
    }
    final context = widget.documentContext;
    if (context == null) return;
    ref.read(aiNotifierProvider.notifier).sendPrompt(prompt, context);
    _controller.clear();
  }

  Future<void> _showHistory() async {
    final AiDocumentContext? document = widget.documentContext;
    if (document == null) return;
    final BuildContext menuContext = context;
    final store = await ref.read(conversationStoreProvider.future);
    final threads = await store.listThreads(document.documentId);
    if (!menuContext.mounted) return;
    final RenderBox button = menuContext.findRenderObject()! as RenderBox;
    final String? selected = await showMenu<String>(
      context: menuContext,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(button.size.width - 200, 48, 1, 1),
        Offset.zero & button.size,
      ),
      items: threads
          .expand(
            (thread) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: thread.id,
                child: Text(thread.title, overflow: TextOverflow.ellipsis),
              ),
              PopupMenuItem<String>(
                value: 'delete:${thread.id}',
                child: const Text('Delete conversation'),
              ),
            ],
          )
          .toList(growable: false),
    );
    if (selected != null && selected.startsWith('delete:')) {
      if (!menuContext.mounted) return;
      final bool? confirmed = await showDialog<bool>(
        context: menuContext,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Delete conversation?'),
          content: const Text(
            'This removes this saved conversation permanently.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref
            .read(aiNotifierProvider.notifier)
            .deleteConversation(selected.substring(7), document.documentId);
      }
    } else if (selected != null) {
      await ref.read(aiNotifierProvider.notifier).selectConversation(selected);
    }
  }
}

class _AgentRunPanel extends StatelessWidget {
  const _AgentRunPanel({
    required this.state,
    required this.currentRevision,
    required this.controller,
  });

  final AgentRunControllerState state;
  final int currentRevision;
  final AgentRunController controller;

  @override
  Widget build(BuildContext context) {
    final proposal = state.pendingProposal;
    if (state.activeRunId == null && proposal == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.progressLabel.isNotEmpty)
            Text(state.progressLabel, key: const Key('agent-progress-label')),
          if (state.assistantText.isNotEmpty) Text(state.assistantText),
          if (proposal != null)
            AgentApprovalCard(
              proposal: proposal,
              currentRevision: currentRevision,
              onApprove: () => unawaited(controller.approve(proposal)),
              onReject: () => unawaited(controller.reject(proposal)),
              onRebase: () =>
                  unawaited(controller.rebase(proposal, currentRevision)),
            ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.providerReady, required this.colors});

  final bool providerReady;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.panelRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: Icon(LucideIcons.fileText, color: colors.accent, size: 25),
            ),
            const SizedBox(height: 18),
            Text(
              'Ask about the document',
              key: Key('ai-empty-title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textStrong,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              providerReady
                  ? 'Clarix will ground answers in the PDF and cite the relevant pages.'
                  : 'Choose a remote AI provider in settings to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentComposer extends StatelessWidget {
  const _DocumentComposer({
    required this.controller,
    required this.enabled,
    required this.isBusy,
    required this.onSend,
    required this.onStop,
    required this.colors,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const Key('document-composer'),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 9),
          decoration: BoxDecoration(
            color: colors.panelRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const Key('document-composer-input'),
                controller: controller,
                enabled: enabled,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                style: TextStyle(
                  color: colors.textStrong,
                  fontSize: 12.5,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: enabled
                      ? 'Ask anything about this document…'
                      : 'Add a provider first',
                  hintStyle: TextStyle(color: colors.textFaint, fontSize: 12.5),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(LucideIcons.fileText, color: colors.textFaint, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Document context',
                      style: TextStyle(
                        color: colors.textFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (BuildContext context, TextEditingValue value, _) {
                      final bool canSend =
                          enabled && value.text.trim().isNotEmpty;
                      return Tooltip(
                        message: isBusy ? 'Stop generating' : 'Send question',
                        child: IconButton(
                          key: const Key('document-composer-send'),
                          onPressed: isBusy
                              ? onStop
                              : (canSend ? onSend : null),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            maximumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            backgroundColor: isBusy
                                ? colors.textMuted
                                : colors.accent,
                            disabledBackgroundColor: colors.border,
                            foregroundColor: colors.canvas,
                            disabledForegroundColor: colors.textFaint,
                          ),
                          icon: Icon(
                            isBusy ? LucideIcons.square : LucideIcons.arrowUp,
                            size: isBusy ? 13 : 16,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.documentContext,
    required this.colors,
  });

  final ComposerMessage message;
  final AiDocumentContext? documentContext;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        MarkdownBody(
          data: message.text.isEmpty ? '...' : message.text,
          extensionSet: markdown.ExtensionSet(
            <markdown.BlockSyntax>[
              ...markdown.ExtensionSet.gitHubFlavored.blockSyntaxes,
              LatexBlockSyntax(),
            ],
            <markdown.InlineSyntax>[
              ...markdown.ExtensionSet.gitHubFlavored.inlineSyntaxes,
              LatexInlineSyntax(),
              if (!isUser) InlinePageReferenceSyntax(),
            ],
          ),
          builders: <String, MarkdownElementBuilder>{
            'latex': LatexElementBuilder(
              textStyle: const TextStyle(
                color: WorkspaceColors.textStrong,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (!isUser)
              'inline-page-reference': InlinePageReferenceBuilder(
                document: documentContext,
                documentRef: null,
                onNavigate: null,
              ),
          },
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 13.5,
              height: 1.45,
            ),
            tableHead: const TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            tableBody: const TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 13.5,
              height: 1.4,
            ),
            tableCellsPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            code: const TextStyle(color: WorkspaceColors.textStrong),
          ),
        ),
      ],
    );

    if (!isUser) {
      return Padding(
        key: const Key('assistant-message-content'),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
        child: SizedBox(width: double.infinity, child: content),
      );
    }

    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            key: const Key('user-message-bubble'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.accentBorder),
            ),
            child: content,
          ),
        );
      },
    );
  }
}

class _ComposerLoadingIndicator extends StatefulWidget {
  const _ComposerLoadingIndicator({required this.colors});

  final WorkspaceSurfaceTokens colors;

  @override
  State<_ComposerLoadingIndicator> createState() =>
      _ComposerLoadingIndicatorState();
}

class _ComposerLoadingIndicatorState extends State<_ComposerLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const List<String> _words = <String>[
    'Reading',
    'Tracing',
    'Grounding',
    'Pondering',
    'Synthesizing',
    'Citing',
  ];

  late final AnimationController _animationController;
  late final Timer _wordTimer;
  int _wordIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _wordTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _wordIndex = (_wordIndex + 1) % _words.length);
      }
    });
  }

  @override
  void dispose() {
    _wordTimer.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('composer-loader'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ScaleTransition(
            scale: Tween<double>(begin: 0.72, end: 1.1).animate(
              CurvedAnimation(
                parent: _animationController,
                curve: Curves.easeInOut,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.colors.accent,
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: 7, height: 7),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _animationController,
            builder: (BuildContext context, Widget? child) => ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (Rect bounds) => LinearGradient(
                colors: const <Color>[
                  WorkspaceColors.textMuted,
                  WorkspaceColors.textStrong,
                  WorkspaceColors.textMuted,
                ],
                stops: <double>[0, _animationController.value, 1],
              ).createShader(bounds),
              child: child,
            ),
            child: Text(
              _words[_wordIndex],
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
