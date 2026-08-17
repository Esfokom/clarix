import 'package:flutter/material.dart';

import '../../../core/agent/agent_bridge_types.dart';
import 'agent_disclosure_dialog.dart';

enum SelectionAiAction { rewrite, shorten, expand, translate, summarize, ask }

extension SelectionAiActionLabel on SelectionAiAction {
  String get label => switch (this) {
    SelectionAiAction.rewrite => 'Rewrite',
    SelectionAiAction.shorten => 'Shorten',
    SelectionAiAction.expand => 'Expand',
    SelectionAiAction.translate => 'Translate',
    SelectionAiAction.summarize => 'Summarize',
    SelectionAiAction.ask => 'Ask Clarix',
  };
}

class SelectionAiToolbar extends StatelessWidget {
  const SelectionAiToolbar({
    required this.hasValidatedSelection,
    required this.sharingEnabled,
    required this.onAction,
    super.key,
  });

  final bool hasValidatedSelection;
  final bool sharingEnabled;
  final ValueChanged<SelectionAiAction> onAction;

  @override
  Widget build(BuildContext context) {
    if (!hasValidatedSelection) return const SizedBox.shrink();
    return Material(
      key: const Key('selection-ai-toolbar'),
      elevation: 5,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Wrap(
              spacing: 4,
              children: <Widget>[
                for (final action in SelectionAiAction.values)
                  TextButton(
                    onPressed: sharingEnabled ? () => onAction(action) : null,
                    child: Text(action.label),
                  ),
              ],
            ),
            if (!sharingEnabled)
              const Text(
                'Enable document sharing for this provider to use selected text.',
              ),
          ],
        ),
      ),
    );
  }
}

class SelectionAiCommandSurface extends StatelessWidget {
  const SelectionAiCommandSurface({
    required this.disclosure,
    required this.sharingEnabled,
    required this.onStart,
    this.includesConversationHistory = true,
    super.key,
  });

  final AgentDisclosure? disclosure;
  final bool sharingEnabled;
  final bool includesConversationHistory;
  final ValueChanged<SelectionAiAction> onStart;

  @override
  Widget build(BuildContext context) => SelectionAiToolbar(
    hasValidatedSelection:
        disclosure != null && disclosure!.selectedText.isNotEmpty,
    sharingEnabled: sharingEnabled,
    onAction: (action) {
      final packet = disclosure;
      if (packet == null || !sharingEnabled) return;
      showDialog<void>(
        context: context,
        builder: (context) => AgentDisclosureDialog(
          disclosure: packet,
          includesConversationHistory: includesConversationHistory,
          onConfirm: () => onStart(action),
        ),
      );
    },
  );
}
