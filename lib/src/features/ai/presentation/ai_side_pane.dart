import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:smooth_corner/smooth_corner.dart';

import 'package:clarix/src/features/ai/ai.dart';
import '../../../core/clarix_logger.dart';
import '../../../core/theme_controller.dart';
import '../../../core/theme_profile.dart';
import '../../../core/workspace_surface_tokens.dart';

part 'ai_composer.dart';
part 'ai_conversation_history.dart';

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
  late final VoiceInputController _voiceInput;

  /// History replaces the transcript in place instead of opening a dialog, so
  /// the pane only ever shows one of the two.
  bool _historyOpen = false;
  bool _historyLoading = false;
  List<ConversationThread> _historyThreads = const <ConversationThread>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _voiceInput = VoiceInputController(
      recorder: ref.read(voiceRecorderProvider),
      transcribe: ref.read(groqTranscriptionServiceProvider).transcribe,
      onTranscript: _appendTranscript,
    );
    unawaited(_restoreSelectedInputDevice());
  }

  @override
  void dispose() {
    _voiceInput.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    final AiWorkspaceState ai = widget.aiState.chat;
    final String? activeThreadId = ai.activeConversationId;
    final String selectedRuntimeLabel =
        widget.aiState.localModels
            .where(
              (LocalModelProfile model) => model.id == ai.selectedProviderId,
            )
            .firstOrNull
            ?.label ??
        widget.aiState.providerProfiles
            .where(
              (AiProviderProfile profile) =>
                  profile.id == ai.selectedProviderId,
            )
            .firstOrNull
            ?.label ??
        'Choose model';
    final String selectedRuntimeIcon =
        selectedRuntimeLabel.toLowerCase().contains('gemma')
        ? 'assets/images/gemma-color.png'
        : selectedRuntimeLabel.toLowerCase().contains('deepseek')
        ? 'assets/images/deepseek.png'
        : 'assets/images/openai.png';
    final composerEnabled =
        ai.providerReady && !ai.chatBusy && widget.documentContext != null;
    final composerHint = !ai.providerReady
        ? 'Add a provider first'
        : widget.documentContext == null
        ? 'Opening document editor…'
        : 'Ask anything about this document…';
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
                  message: _historyOpen
                      ? 'Hide conversation history'
                      : 'Conversation history',
                  child: ShadIconButton.ghost(
                    key: const Key('ai-conversation-history'),
                    width: 28,
                    height: 28,
                    padding: EdgeInsets.zero,
                    foregroundColor: _historyOpen ? colors.accent : null,
                    icon: const Icon(LucideIcons.history, size: 14),
                    onPressed: ai.chatBusy || widget.documentContext == null
                        ? null
                        : _toggleHistory,
                  ),
                ),
                // While history is open the pinned action below owns starting a
                // new conversation, so the header keeps only one way to do it.
                if (!_historyOpen) ...<Widget>[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'New conversation',
                    child: ShadIconButton.ghost(
                      key: const Key('ai-new-conversation'),
                      width: 28,
                      height: 28,
                      padding: EdgeInsets.zero,
                      icon: const Icon(LucideIcons.squarePen, size: 14),
                      onPressed: ai.chatBusy ? null : _startNewConversation,
                    ),
                  ),
                ],
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
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (Widget? current, List<Widget> previous) =>
                  Stack(
                    fit: StackFit.expand,
                    children: <Widget>[...previous, ?current],
                  ),
              transitionBuilder: (Widget child, Animation<double> animation) {
                // The history slides in from the side it lives on, so the two
                // views read as one surface sliding rather than a hard cut.
                final bool isHistory =
                    child.key == const ValueKey<String>('ai-history');
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0, isHistory ? 0.035 : -0.02),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _historyOpen
                  ? _ConversationHistoryPanel(
                      key: const ValueKey<String>('ai-history'),
                      threads: _historyThreads,
                      isLoading: _historyLoading,
                      activeThreadId: activeThreadId,
                      colors: colors,
                      onOpen: _openConversation,
                      onDelete: _confirmDeleteConversation,
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('ai-chat'),
                      child: ai.messages.isEmpty
                          ? _EmptyConversation(
                              providerReady: ai.providerReady,
                              colors: colors,
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(12),
                              itemCount: ai.messages.length,
                              itemBuilder:
                                  (BuildContext context, int index) {
                                    final ComposerMessage message = ai
                                        .messages[ai.messages.length -
                                        1 -
                                        index];
                                    return _MessageBubble(
                                      message: message,
                                      documentContext: widget.documentContext,
                                      colors: colors,
                                    );
                                  },
                            ),
                    ),
            ),
          ),
          if (_historyOpen)
            _PinnedNewConversationBar(
              colors: colors,
              onPressed: ai.chatBusy ? null : _startNewConversation,
            )
          else ...<Widget>[
            if (ai.chatBusy)
              _ComposerLoadingIndicator(
                colors: colors,
                statusMessage: ai.statusMessage,
              ),
            _DocumentComposer(
              controller: _controller,
              voiceInput: _voiceInput,
              enabled: composerEnabled,
              isBusy: ai.chatBusy,
              hintText: composerHint,
              onSend: _send,
              colors: colors,
              onStop: () =>
                  ref.read(aiNotifierProvider.notifier).stopGeneration(),
              runtimeLabel: selectedRuntimeLabel,
              runtimeIconPath: selectedRuntimeIcon,
              selectedRuntimeId: ai.selectedProviderId,
              localModels: widget.aiState.localModels,
              providerProfiles: widget.aiState.providerProfiles,
              onSelectRuntime: _selectRuntime,
              runtimePickerEnabled: !ai.chatBusy,
              contextPercent: contextPercent,
              estimatedTokens: estimatedTokens,
              contextLimit: contextLimit,
            ),
          ],
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

  void _appendTranscript(String transcript) {
    final String existing = _controller.text;
    final String separator = existing.trim().isEmpty ? '' : ' ';
    final String updated = '$existing$separator$transcript';
    _controller.value = _controller.value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _restoreSelectedInputDevice() async {
    try {
      final String? deviceId = await ref
          .read(voiceInputSettingsStoreProvider)
          .readSelectedDeviceId();
      if (deviceId != null) await _voiceInput.selectInputDevice(deviceId);
    } catch (_) {
      await ref
          .read(voiceInputSettingsStoreProvider)
          .saveSelectedDeviceId(null);
    }
  }

  /// Switches models in place: the transcript carries over, and each reply
  /// already records the model that produced it.
  Future<void> _selectRuntime(String id) async {
    if (id == widget.aiState.chat.selectedProviderId) return;
    await ref.read(aiNotifierProvider.notifier).selectProvider(id);
  }

  void _startNewConversation() {
    setState(() => _historyOpen = false);
    unawaited(ref.read(aiNotifierProvider.notifier).startNewConversation());
  }

  Future<void> _toggleHistory() async {
    if (_historyOpen) {
      setState(() => _historyOpen = false);
      return;
    }
    setState(() {
      _historyOpen = true;
      _historyLoading = _historyThreads.isEmpty;
    });
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    final AiDocumentContext? document = widget.documentContext;
    if (document == null) return;
    try {
      final store = await ref.read(conversationStoreProvider.future);
      final List<ConversationThread> threads = await store.listThreads(
        document.documentId,
      );
      if (!mounted) return;
      setState(() {
        _historyThreads = threads;
        _historyLoading = false;
      });
    } catch (error, stackTrace) {
      clarixLog.w(
        'Loading conversation history failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _openConversation(String threadId) async {
    // Close first: the transcript animates in over the freshly loaded
    // messages rather than after them.
    setState(() => _historyOpen = false);
    await ref.read(aiNotifierProvider.notifier).selectConversation(threadId);
  }

  Future<void> _confirmDeleteConversation(ConversationThread thread) async {
    final AiDocumentContext? document = widget.documentContext;
    if (document == null) return;
    final bool confirmed =
        await _confirm(
          title: 'Delete conversation?',
          description: 'This removes this saved conversation permanently.',
          confirmLabel: 'Delete',
          destructive: true,
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await ref
        .read(aiNotifierProvider.notifier)
        .deleteConversation(thread.id, document.documentId);
    await _loadHistory();
  }

  /// Confirmation styled with the workspace surface tokens, so it reads as
  /// part of the app rather than a stock Material alert.
  Future<bool?> _confirm({
    required String title,
    required String description,
    required String confirmLabel,
    bool destructive = false,
  }) {
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    return showShadDialog<bool>(
      context: context,
      barrierColor: colors.backdrop,
      builder: (BuildContext dialogContext) => ShadDialog(
        radius: BorderRadius.circular(18),
        backgroundColor: colors.panel,
        border: Border.all(color: colors.border),
        constraints: const BoxConstraints(maxWidth: 380),
        title: Text(
          title,
          style: TextStyle(
            color: colors.textStrong,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        description: Text(
          description,
          style: TextStyle(color: colors.textMuted, fontSize: 12.5),
        ),
        actions: <Widget>[
          ShadButton.outline(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            backgroundColor: destructive ? colors.warning : colors.accent,
            foregroundColor: colors.canvas,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
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
              textStyle: TextStyle(
                color: colors.textStrong,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (!isUser)
              'inline-page-reference': InlinePageReferenceBuilder(
                document: documentContext,
                documentRef: null,
                onNavigate: null,
                colors: colors,
              ),
          },
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: colors.textStrong,
              fontSize: 13.5,
              height: 1.45,
            ),
            tableHead: TextStyle(
              color: colors.textStrong,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            tableBody: TextStyle(
              color: colors.textStrong,
              fontSize: 13.5,
              height: 1.4,
            ),
            tableCellsPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            code: TextStyle(color: colors.textStrong),
          ),
        ),
      ],
    );

    if (!isUser) {
      return Padding(
        key: const Key('assistant-message-content'),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              content,
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      message.modelLabel == null
                          ? 'Responded by selected model'
                          : 'Responded by ${message.modelLabel}',
                      key: Key('assistant-model-${message.id}'),
                      style: TextStyle(color: colors.textFaint, fontSize: 10.5),
                    ),
                  ),
                  IconButton(
                    key: Key('copy-assistant-response-${message.id}'),
                    tooltip: 'Copy response',
                    icon: Icon(
                      LucideIcons.copy,
                      color: colors.textFaint,
                      size: 14,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: message.text),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
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
