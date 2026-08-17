import 'package:flutter/material.dart';

import '../../../../core/agent/agent_bridge_types.dart';

class AgentDisclosureDialog extends StatelessWidget {
  const AgentDisclosureDialog({
    required this.disclosure,
    required this.includesConversationHistory,
    required this.onConfirm,
    super.key,
  });

  final AgentDisclosure disclosure;
  final bool includesConversationHistory;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('agent-disclosure-preview'),
    title: const Text('Share selection with provider?'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Provider: ${disclosure.providerLabel}'),
            const SizedBox(height: 12),
            const Text('Selected text'),
            SelectableText(disclosure.selectedText),
            if (disclosure.nearbyTextBefore.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text('Nearby text before'),
              SelectableText(disclosure.nearbyTextBefore),
            ],
            if (disclosure.nearbyTextAfter.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const Text('Nearby text after'),
              SelectableText(disclosure.nearbyTextAfter),
            ],
            const SizedBox(height: 12),
            Text('Pages: ${disclosure.pageNumbers.join(', ')}'),
            Text(
              includesConversationHistory
                  ? 'Conversation history will be included.'
                  : 'Conversation history will not be included.',
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.of(context).pop();
          onConfirm();
        },
        child: const Text('Share and continue'),
      ),
    ],
  );
}
