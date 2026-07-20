import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
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
                  icon: const Icon(LucideIcons.cpu, size: 14),
                  onPressed: () => ref
                      .read(workspaceNotifierProvider.notifier)
                      .toggleProviderSettings(true),
                ),
                const SizedBox(width: 4),
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (_isBusyPhase(ai.activityPhase)) ...<Widget>[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ] else ...<Widget>[
                      Icon(
                        _phaseIcon(ai.activityPhase),
                        size: 12,
                        color: WorkspaceColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: ShadBadge.secondary(
                        child: Text(
                          ai.statusMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.state.providerProfiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                _providerDisclosure(ai),
                style: const TextStyle(
                  color: WorkspaceColors.textMuted,
                  fontSize: 10.5,
                ),
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
                      return _MessageBubble(message: message);
                    },
                  ),
          ),
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
                  enabled: ai.providerReady && !ai.chatBusy,
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

  bool _isBusyPhase(AiRuntimePhase phase) {
    return phase == AiRuntimePhase.restoringInference ||
        phase == AiRuntimePhase.restoringEmbedding ||
        phase == AiRuntimePhase.loadingInference ||
        phase == AiRuntimePhase.preparingGrounding ||
        phase == AiRuntimePhase.indexing ||
        phase == AiRuntimePhase.retrieving ||
        phase == AiRuntimePhase.generating;
  }

  IconData _phaseIcon(AiRuntimePhase phase) {
    return switch (phase) {
      AiRuntimePhase.failed => LucideIcons.triangleAlert,
      AiRuntimePhase.idle => LucideIcons.cpu,
      _ => LucideIcons.cpu,
    };
  }

  String _providerDisclosure(AiWorkspaceState ai) {
    final profile = widget.state.providerProfiles
        .where((item) => item.id == ai.selectedProviderId)
        .firstOrNull;
    if (profile == null) return 'Remote provider not selected';
    return '${profile.label} · Remote${profile.shareRetrievedPassages ? ' — Retrieved PDF passages may be shared' : ' — PDF passages stay local'}';
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ComposerMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isUser
              ? WorkspaceColors.accentSoft
              : WorkspaceColors.panelRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUser
                ? WorkspaceColors.accentBorder
                : WorkspaceColors.border,
          ),
        ),
        child: Text(
          message.text.isEmpty ? '...' : message.text,
          style: const TextStyle(
            color: WorkspaceColors.textStrong,
            fontSize: 11.5,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
