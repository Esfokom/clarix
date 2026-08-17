import 'package:flutter/material.dart';

import '../../../core/agent/agent_bridge_types.dart';

class AgentDiffOverlay extends StatelessWidget {
  const AgentDiffOverlay({required this.proposal, super.key});

  final AgentProposal proposal;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Semantics(
      label: 'Proposed document changes',
      child: DecoratedBox(
        key: const Key('agent-diff-overlay'),
        decoration: BoxDecoration(
          color: const Color(0x14f59e0b),
          border: Border.all(color: const Color(0xfff59e0b)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final target in proposal.targets)
                Text('${target.beforeText} → ${target.afterText}'),
            ],
          ),
        ),
      ),
    ),
  );
}
