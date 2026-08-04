import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import 'inline_page_reference.dart';
import 'workspace_common.dart';

class AiSidePane extends ConsumerStatefulWidget {
  const AiSidePane({required this.state, required this.activeTab, super.key});

  final WorkspaceFeatureState state;
  final DocumentTabState? activeTab;

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
    final AiWorkspaceState ai = widget.state.aiState;

    return DecoratedBox(
      decoration: const BoxDecoration(color: WorkspaceColors.panel),
      child: Column(
        children: <Widget>[
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Clarix AI',
                    style: TextStyle(
                      color: WorkspaceColors.textStrong,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ShadIconButton.ghost(
                  width: 28,
                  height: 28,
                  padding: EdgeInsets.zero,
                  icon: const Icon(LucideIcons.chevronRight, size: 14),
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .toggleComposerExpanded(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.activeTab == null
                        ? 'No active PDF'
                        : widget.activeTab!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkspaceColors.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Current PDF',
                  style: TextStyle(
                    color: WorkspaceColors.textFaint,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(width: 6),
                ShadSwitch(
                  value: ai.useCurrentDocumentScope,
                  onChanged: (bool _) => ref
                      .read(workspaceNotifierProvider.notifier)
                      .toggleScopeMode(),
                  width: 34,
                  height: 20,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: WorkspaceColors.border),
          Expanded(
            child: ai.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        ai.providerReady
                            ? 'Ask about the active PDF, summarize a section, or query all open documents.'
                            : 'Choose a remote AI provider in settings to enable chat.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: WorkspaceColors.textMuted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ),
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
                        activeTab: widget.activeTab,
                      );
                    },
                  ),
          ),
          if (ai.chatBusy) const _ComposerLoadingIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ShadInput(
                    controller: _controller,
                    enabled: ai.providerReady && !ai.chatBusy,
                    placeholder: Text(
                      ai.providerReady
                          ? 'Ask Clarix AI'
                          : 'Add a provider first',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                ShadIconButton(
                  width: 32,
                  height: 32,
                  padding: EdgeInsets.zero,
                  enabled: ai.providerReady,
                  icon: ai.chatBusy
                      ? const Icon(LucideIcons.square, size: 14)
                      : const Icon(LucideIcons.arrowUp, size: 14),
                  onPressed: ai.chatBusy
                      ? () => ref
                            .read(workspaceNotifierProvider.notifier)
                            .stopGeneration()
                      : _send,
                ),
              ],
            ),
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
    ref.read(workspaceNotifierProvider.notifier).sendPrompt(prompt);
    _controller.clear();
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.activeTab});

  final ComposerMessage message;
  final DocumentTabState? activeTab;

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
            <markdown.BlockSyntax>[LatexBlockSyntax()],
            <markdown.InlineSyntax>[
              LatexInlineSyntax(),
              if (!isUser) InlinePageReferenceSyntax(),
            ],
          ),
          builders: <String, MarkdownElementBuilder>{
            'latex': LatexElementBuilder(
              textStyle: const TextStyle(
                color: WorkspaceColors.textStrong,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            if (!isUser)
              'inline-page-reference': InlinePageReferenceBuilder(
                activeTab: activeTab,
              ),
          },
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(
              color: WorkspaceColors.textStrong,
              fontSize: 11.5,
              height: 1.45,
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

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: const Key('user-message-bubble'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: WorkspaceColors.accentSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WorkspaceColors.accentBorder),
        ),
        child: content,
      ),
    );
  }
}

class _ComposerLoadingIndicator extends StatefulWidget {
  const _ComposerLoadingIndicator();

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
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: WorkspaceColors.accent,
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
