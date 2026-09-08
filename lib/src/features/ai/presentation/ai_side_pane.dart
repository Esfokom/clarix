import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:clarix/src/features/ai/ai.dart';
import '../../../core/clarix_logger.dart';
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
    final composerEnabled =
        ai.providerReady && !ai.chatBusy && widget.documentContext != null;
    final composerHint = !ai.providerReady
        ? 'Add a provider first'
        : widget.documentContext == null
        ? 'Opening document editor…'
        : 'Ask anything about this document…';
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
          _ProviderSelectorBar(aiState: widget.aiState, colors: colors),
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
            enabled: composerEnabled,
            isBusy: ai.chatBusy,
            hintText: composerHint,
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
      clarixLog.t('AI composer send ignored: empty prompt.');
      return;
    }
    final context = widget.documentContext;
    if (context == null) {
      clarixLog.w(
        'AI composer send ignored: native document context is unavailable.',
      );
      return;
    }
    clarixLog.i(
      'AI composer send requested for tab ${context.tabId} '
      '(${prompt.length} characters).',
    );
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
    required this.hintText,
    required this.onSend,
    required this.onStop,
    required this.colors,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isBusy;
  final String hintText;
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
                  hintText: hintText,
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
    final Widget content = SelectionArea(
      child: Column(
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
      ),
    );

    if (!isUser) {
      return Padding(
        key: const Key('assistant-message-content'),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            content,
            const SizedBox(height: 4),
            InkWell(
              onTap: () async {
                final cleanText = message.text
                    .replaceAll(RegExp(r'\[\[EDIT_TEXT:.*?\]\]'), '')
                    .replaceAll(RegExp(r'\[\[SCROLL_TO_PAGE:.*?\]\]'), '')
                    .replaceAll(RegExp(r'\[\[CREATE_SOLUTION_PDF:.*?\]\]'), '')
                    .replaceAll(RegExp(r'\[\[SAVE_DOCUMENT:.*?\]\]'), '')
                    .trim();
                await Clipboard.setData(ClipboardData(text: cleanText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(LucideIcons.copy, size: 12, color: colors.textFaint),
                    const SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: TextStyle(color: colors.textFaint, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                key: const Key('user-message-bubble'),
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.accentBorder),
                ),
                child: content,
              ),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: message.text.trim()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Prompt copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(LucideIcons.copy, size: 11, color: colors.textFaint),
                      const SizedBox(width: 3),
                      Text(
                        'Copy',
                        style: TextStyle(color: colors.textFaint, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
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

class _ProviderSelectorBar extends ConsumerWidget {
  const _ProviderSelectorBar({
    required this.aiState,
    required this.colors,
  });

  final AiFeatureState aiState;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = aiState.providerProfiles;
    final selectedId = aiState.chat.selectedProviderId;
    final selectedProfile =
        profiles.where((p) => p.id == selectedId).firstOrNull ??
            profiles.firstOrNull;

    final isOffline = selectedProfile?.baseUrl.contains('localhost') == true ||
        selectedProfile?.baseUrl.contains('127.0.0.1') == true ||
        selectedProfile?.id.contains('local') == true ||
        selectedProfile?.id.contains('gemma') == true;

    final label = selectedProfile?.label ?? 'Select Provider';
    final accentColor =
        isOffline ? const Color(0xFF71717A) : const Color(0xFF3B82F6);
    final badgeText = isOffline ? '100% Offline' : 'Cloud API';
    final icon =
        isOffline ? LucideIcons.laptop : LucideIcons.cloud;

    final offlineProfiles = profiles
        .where(
          (p) =>
              p.baseUrl.contains('localhost') ||
              p.baseUrl.contains('127.0.0.1') ||
              p.id.contains('local') ||
              p.id.contains('gemma'),
        )
        .toList();

    final onlineProfiles =
        profiles.where((p) => !offlineProfiles.contains(p)).toList();

    return InkWell(
      onTap: () => _showProviderMenu(
        context,
        ref,
        offlineProfiles,
        onlineProfiles,
        selectedProfile?.id,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.06),
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 13, color: accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textStrong,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    badgeText,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronDown, size: 13, color: colors.textFaint),
          ],
        ),
      ),
    );
  }

  void _showProviderMenu(
    BuildContext context,
    WidgetRef ref,
    List<AiProviderProfile> offline,
    List<AiProviderProfile> online,
    String? selectedId,
  ) {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero) & box.size,
      Offset.zero & MediaQuery.of(context).size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '🏠 OFFLINE LOCAL MODELS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFFA1A1AA),
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...offline.map(
          (profile) => PopupMenuItem<String>(
            value: profile.id,
            child: Row(
              children: <Widget>[
                Icon(
                  profile.id == selectedId
                      ? LucideIcons.check
                      : LucideIcons.circle,
                  size: 14,
                  color: profile.id == selectedId
                      ? const Color(0xFFFAFAFA)
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        profile.label,
                        style: TextStyle(
                          fontWeight: profile.id == selectedId
                              ? FontWeight.w700
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${profile.modelId} · No Internet',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (profile.id == selectedId)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F3F46),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFAFAFA),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (online.isNotEmpty) ...<PopupMenuEntry<String>>[
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            enabled: false,
            child: Text(
              '☁️ ONLINE CLOUD MODELS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3B82F6),
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...online.map(
            (profile) => PopupMenuItem<String>(
              value: profile.id,
              child: Row(
                children: <Widget>[
                  Icon(
                    profile.id == selectedId
                        ? LucideIcons.check
                        : LucideIcons.circle,
                    size: 14,
                    color: profile.id == selectedId
                        ? const Color(0xFF3B82F6)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          profile.label,
                          style: TextStyle(
                            fontWeight: profile.id == selectedId
                                ? FontWeight.w700
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${profile.modelId} · Cloud API',
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (profile.id == selectedId)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    ).then((profileId) {
      if (profileId != null) {
        ref.read(aiNotifierProvider.notifier).selectProvider(profileId);
      }
    });
  }
}
