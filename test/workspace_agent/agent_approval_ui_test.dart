import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/features/workspace/agent/presentation/agent_approval_card.dart';
import 'package:clarix/src/features/workspace/agent/presentation/agent_diff_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentProposal proposal({int revision = 4}) => AgentProposal(
  runId: '00000000-0000-4000-8000-000000000001',
  proposalId: '00000000-0000-4000-8000-000000000002',
  approvalId: '00000000-0000-4000-8000-000000000003',
  baseRevision: revision,
  digestSha256: 'a' * 64,
  toolName: 'replace_text_range',
  targets: const <AgentProposalTarget>[
    AgentProposalTarget(
      objectId: '00000000-0000-4000-8000-000000000004',
      pageId: '00000000-0000-4000-8000-000000000005',
      pageNumber: 1,
      startUtf16: 0,
      endUtf16: 3,
      beforeText: 'old',
      afterText: 'new',
    ),
  ],
  reasons: const <String>['changes multiple targets'],
);

Widget harness(AgentProposal proposal, {required int currentRevision}) =>
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            const Text('Accepted text: old'),
            AgentDiffOverlay(proposal: proposal),
            AgentApprovalCard(
              proposal: proposal,
              currentRevision: currentRevision,
              onApprove: () {},
              onReject: () {},
              onRebase: () {},
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets(
    'risky proposal paints a diff but does not change accepted text',
    (tester) async {
      await tester.pumpWidget(harness(proposal(), currentRevision: 4));
      expect(find.byKey(const Key('agent-diff-overlay')), findsOneWidget);
      expect(find.text('Accepted text: old'), findsOneWidget);
      expect(find.byKey(const Key('agent-approve')), findsOneWidget);
    },
  );

  testWidgets('revision conflict offers rebase and never stale approval', (
    tester,
  ) async {
    await tester.pumpWidget(harness(proposal(), currentRevision: 5));
    expect(find.text('Document changed'), findsOneWidget);
    expect(find.byKey(const Key('agent-rebase')), findsOneWidget);
    expect(find.byKey(const Key('agent-approve')), findsNothing);
  });
}
