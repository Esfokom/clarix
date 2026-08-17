import 'package:flutter/material.dart';

import '../../../core/agent/agent_bridge_types.dart';

class AgentApprovalCard extends StatelessWidget {
  const AgentApprovalCard({
    required this.proposal,
    required this.currentRevision,
    required this.onApprove,
    required this.onReject,
    required this.onRebase,
    super.key,
  });

  final AgentProposal proposal;
  final int currentRevision;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRebase;

  @override
  Widget build(BuildContext context) {
    final stale = currentRevision != proposal.baseRevision;
    return Card(
      key: const Key('agent-approval-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(stale ? 'Document changed' : 'Review proposed edit'),
            if (proposal.reasons.isNotEmpty) Text(proposal.reasons.join(' · ')),
            for (final target in proposal.targets) ...<Widget>[
              const SizedBox(height: 8),
              Text('Before: ${target.beforeText}'),
              Text('After: ${target.afterText}'),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                TextButton(
                  key: const Key('agent-reject'),
                  onPressed: onReject,
                  child: const Text('Reject'),
                ),
                if (stale)
                  FilledButton(
                    key: const Key('agent-rebase'),
                    onPressed: onRebase,
                    child: const Text('Rebase'),
                  )
                else
                  FilledButton(
                    key: const Key('agent-approve'),
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
