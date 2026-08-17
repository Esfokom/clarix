import 'package:clarix/src/core/agent/agent_bridge.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/features/ai/application/agent_run_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/agent/agent_bridge_contract_test.dart'
    show FakeNativeAgentPort, runId, sessionId;

void main() {
  test(
    'generic conversation uses native run protocol without a selection',
    () async {
      final native = _CapturingPort(<NativeAgentEventWire>[
        const NativeAgentEventWire(
          schemaVersion: 1,
          sessionId: sessionId,
          runId: runId,
          sequence: 1,
          documentRevision: 4,
          kind: 'textDelta',
          payloadJson: '{"TextDelta":{"text":"Hello"}}',
        ),
        const NativeAgentEventWire(
          schemaVersion: 1,
          sessionId: sessionId,
          runId: runId,
          sequence: 2,
          documentRevision: 4,
          kind: 'statusChanged',
          payloadJson: '{"StatusChanged":{"status":"Completed"}}',
        ),
        const NativeAgentEventWire(
          schemaVersion: 1,
          sessionId: sessionId,
          runId: runId,
          sequence: 3,
          documentRevision: 4,
          kind: 'finished',
          payloadJson: '{"Finished":{"outcome":"Completed"}}',
        ),
      ]);
      final controller = AgentRunController(
        bridge: AgentBridgeSession.forTest(native, sessionId: sessionId),
      );
      final terminal = controller.changes.firstWhere(
        (state) => state.status?.isTerminal ?? false,
      );
      await controller.start(
        const AgentStartRequest(
          providerEndpoint: 'https://example.invalid/v1',
          modelId: 'model',
          headers: <String, String>{},
          apiKey: 'secret',
          conversationId: 'legacy-thread-id',
          userPrompt: 'Hello',
        ),
      );
      final state = await terminal;
      expect(native.request!.selection, isNull);
      expect(native.request!.disclosureSha256, isNull);
      expect(native.request!.conversationId, 'legacy-thread-id');
      expect(state.assistantText, 'Hello');
      expect(state.lastSequence, 2);
      await controller.dispose();
    },
  );
}

class _CapturingPort extends FakeNativeAgentPort {
  _CapturingPort(super.events);
  AgentStartRequest? request;

  @override
  Future<NativeAgentRunWire> start(AgentStartRequest value) {
    request = value;
    return super.start(value);
  }
}
