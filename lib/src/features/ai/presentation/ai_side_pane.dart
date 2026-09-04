import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final VoiceInputController _voiceInput;

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
    );
    final AiWorkspaceState ai = widget.aiState.chat;
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
                      ? 'Back to conversation'
                      : 'Conversation history',
                  child: ShadIconButton.ghost(
                    key: const Key('ai-conversation-history'),
                    width: 28,
                    height: 28,
                    padding: EdgeInsets.zero,
                    foregroundColor: _historyOpen ? colors.accent : null,
                    icon: Icon(
                      _historyOpen ? LucideIcons.x : LucideIcons.history,
                      size: 14,
                    ),
                    onPressed: ai.chatBusy || widget.documentContext == null
                        ? null
                        : _toggleHistory,
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
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (Widget? current, List<Widget> previous) =>
                  Stack(
                    fit: StackFit.expand,
                    children: <Widget>[...previous, if (current != null) current],
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
                      activeThreadId: _activeThreadId,
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

  Future<void> _selectRuntime(String id) async {
    final AiWorkspaceState chat = widget.aiState.chat;
    if (id == chat.selectedProviderId) return;
    if (chat.messages.isNotEmpty) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Start a new conversation?'),
          content: const Text('Changing models starts a new conversation.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Change model'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await ref.read(aiNotifierProvider.notifier).startNewConversation();
    }
    if (mounted) {
      await ref.read(aiNotifierProvider.notifier).selectProvider(id);
    }
  }

  Future<void> _showHistory() async {
    final AiDocumentContext? document = widget.documentContext;
    if (document == null) return;
    final BuildContext menuContext = context;
    final store = await ref.read(conversationStoreProvider.future);
    final threads = await store.listThreads(document.documentId);
    if (!menuContext.mounted) return;
    final String? selected = await showDialog<String>(
      context: menuContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Conversation history'),
        content: SizedBox(
          width: 420,
          child: threads.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('No saved conversations for this document yet.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final thread = threads[index];
                    return ListTile(
                      key: Key('conversation-thread-${thread.id}'),
                      title: Text(
                        thread.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Updated ${thread.updatedAt.toLocal()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(dialogContext, thread.id),
                      trailing: IconButton(
                        tooltip: 'Delete conversation',
                        icon: const Icon(LucideIcons.trash2, size: 16),
                        onPressed: () =>
                            Navigator.pop(dialogContext, 'delete:${thread.id}'),
                      ),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
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

class _RuntimeMenuItem extends StatelessWidget {
  const _RuntimeMenuItem({required this.label, required this.iconPath});

  final String label;
  final String iconPath;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Image.asset(iconPath, width: 20, height: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
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
    required this.voiceInput,
    required this.enabled,
    required this.isBusy,
    required this.hintText,
    required this.onSend,
    required this.onStop,
    required this.colors,
  });

  final TextEditingController controller;
  final VoiceInputController voiceInput;
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
              AnimatedBuilder(
                animation: voiceInput,
                builder: (BuildContext context, Widget? child) {
                  final bool isRecording =
                      voiceInput.status == VoiceInputStatus.recording;
                  final bool isTranscribing =
                      voiceInput.status == VoiceInputStatus.transcribing;
                  final String contextLabel = isTranscribing
                      ? 'Transcribing voice…'
                      : voiceInput.errorMessage ?? 'Document context';
                  return Row(
                    children: <Widget>[
                      Icon(
                        LucideIcons.fileText,
                        color: colors.textFaint,
                        size: 13,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          contextLabel,
                          key: const Key('voice-input-status'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: voiceInput.errorMessage == null
                                ? colors.textFaint
                                : colors.warning,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: isRecording
                            ? 'Stop recording'
                            : isTranscribing
                            ? 'Transcribing voice input'
                            : 'Start voice input',
                        child: IconButton(
                          key: const Key('document-composer-voice'),
                          onPressed:
                              isTranscribing || (!enabled && !isRecording)
                              ? null
                              : voiceInput.toggle,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            maximumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            backgroundColor: isRecording
                                ? colors.warning
                                : colors.panelRaised,
                            disabledBackgroundColor: colors.border,
                            foregroundColor: isRecording
                                ? colors.canvas
                                : colors.textMuted,
                            disabledForegroundColor: colors.textFaint,
                          ),
                          icon: isTranscribing
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: colors.textFaint,
                                  ),
                                )
                              : Icon(
                                  isRecording
                                      ? LucideIcons.square
                                      : LucideIcons.mic,
                                  size: isRecording ? 13 : 16,
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder:
                            (BuildContext context, TextEditingValue value, _) {
                              final bool canSend =
                                  enabled &&
                                  !isRecording &&
                                  !isTranscribing &&
                                  value.text.trim().isNotEmpty;
                              return Tooltip(
                                message: isBusy
                                    ? 'Stop generating'
                                    : 'Send question',
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
                                    isBusy
                                        ? LucideIcons.square
                                        : LucideIcons.arrowUp,
                                    size: isBusy ? 13 : 16,
                                  ),
                                ),
                              );
                            },
                      ),
                    ],
                  );
                },
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
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Response copied.')),
                        );
                      }
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

class _ComposerLoadingIndicator extends StatefulWidget {
  const _ComposerLoadingIndicator({
    required this.colors,
    required this.statusMessage,
  });

  final WorkspaceSurfaceTokens colors;
  final String statusMessage;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.statusMessage,
            key: const Key('ai-runtime-status'),
            style: TextStyle(color: widget.colors.textFaint, fontSize: 10.5),
          ),
          const SizedBox(height: 4),
          Row(
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
        ],
      ),
    );
  }
}
