import 'package:clarix/src/core/agent/agent_bridge.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/features/ai/application/agent_run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/agent/agent_bridge_contract_test.dart'
    show FakeNativeAgentPort, request, sessionId, runId;

void main() {
  test(
    'controller keeps one active run per tab and rejects cross-run approval',
    () async {
      final bridge = AgentBridgeSession.forTest(
        FakeNativeAgentPort(const <NativeAgentEventWire>[]),
        sessionId: sessionId,
      );
      final controller = AgentRunController(bridge: bridge);
      final run = await controller.start(request());
      final foreign = AgentProposal(
        runId: '00000000-0000-4000-8000-000000000099',
        proposalId: '00000000-0000-4000-8000-000000000098',
        approvalId: '00000000-0000-4000-8000-000000000097',
        baseRevision: 4,
        digestSha256: 'digest',
      );

      await expectLater(
        controller.approve(foreign),
        throwsA(isA<StateError>()),
      );
      expect(controller.state.activeRunId, run.runId);
      expect(run.runId, runId);
      await controller.dispose();
    },
  );

  test(
    'controller does not mark a commit before native commandCommitted event',
    () async {
      final bridge = AgentBridgeSession.forTest(
        FakeNativeAgentPort(const <NativeAgentEventWire>[]),
        sessionId: sessionId,
      );
      final controller = AgentRunController(bridge: bridge);
      await controller.start(request());

      expect(controller.state.committedRevision, isNull);
      await controller.dispose();
    },
  );
}
