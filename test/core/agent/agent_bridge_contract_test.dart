import 'dart:async';

import 'package:clarix/src/core/agent/agent_bridge.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:flutter_test/flutter_test.dart';

const sessionId = '00000000-0000-4000-8000-000000000001';
const runId = '00000000-0000-4000-8000-000000000002';

class FakeNativeAgentPort implements NativeAgentPort {
  FakeNativeAgentPort(this.wireEvents);

  final List<NativeAgentEventWire> wireEvents;

  @override
  Stream<NativeAgentEventWire> events(String ignoredRunId) =>
      Stream<NativeAgentEventWire>.fromIterable(wireEvents);

  @override
  Future<NativeAgentRunWire> start(AgentStartRequest request) async =>
      const NativeAgentRunWire(
        schemaVersion: 1,
        runId: runId,
        status: 'queued',
      );

  @override
  Future<NativeAgentRunWire> approve(
    String ignoredRunId,
    String approvalId,
  ) async => const NativeAgentRunWire(
    schemaVersion: 1,
    runId: runId,
    status: 'completed',
  );

  @override
  Future<NativeAgentRunWire> reject(String ignoredRunId, String approvalId) =>
      approve(ignoredRunId, approvalId);

  @override
  Future<NativeAgentRunWire> rebase(
    String ignoredRunId,
    String approvalId,
    int currentRevision,
  ) => approve(ignoredRunId, approvalId);

  @override
  Future<void> cancel(String ignoredRunId) async {}
}

NativeAgentEventWire event(int sequence) => NativeAgentEventWire(
  schemaVersion: 1,
  sessionId: sessionId,
  runId: runId,
  sequence: sequence,
  documentRevision: 4,
  kind: 'textDelta',
  payloadJson: '{"TextDelta":{"text":"x"}}',
);

AgentStartRequest request() => const AgentStartRequest(
  providerEndpoint: 'https://example.invalid/v1',
  modelId: 'model',
  headers: <String, String>{},
  apiKey: 'secret',
  userPrompt: 'rewrite',
  selection: AgentSelection(
    revision: 4,
    ranges: <AgentSelectionRange>[],
    objectIds: <String>[],
  ),
  disclosureSha256: 'digest',
);

void main() {
  test(
    'bridge rejects duplicate or decreasing agent event sequences',
    () async {
      final bridge = AgentBridgeSession.forTest(
        FakeNativeAgentPort(<NativeAgentEventWire>[event(1), event(1)]),
        sessionId: sessionId,
      );
      await bridge.start(request());

      await expectLater(
        bridge.events,
        emitsInOrder(<dynamic>[
          isA<AgentRunEvent>(),
          emitsError(isA<AgentProtocolViolation>()),
        ]),
      );
    },
  );

  test(
    'bridge rejects mismatched sessions and events after terminal state',
    () async {
      final terminal = event(1).copyWith(
        kind: 'finished',
        payloadJson: '{"Finished":{"outcome":"Completed"}}',
      );
      final bridge = AgentBridgeSession.forTest(
        FakeNativeAgentPort(<NativeAgentEventWire>[terminal, event(2)]),
        sessionId: sessionId,
      );
      await bridge.start(request());

      await expectLater(
        bridge.events,
        emitsInOrder(<dynamic>[
          isA<AgentRunEvent>(),
          emitsError(isA<AgentProtocolViolation>()),
        ]),
      );
    },
  );
}
