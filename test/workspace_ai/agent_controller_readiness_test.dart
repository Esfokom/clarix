import 'dart:async';

import 'package:clarix/src/core/agent/agent_bridge.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/pdf_editor/application/editor_session_registry.dart';
import 'package:clarix/src/features/pdf_editor/infrastructure/editor_session_gateway.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'agent controller becomes available after the editor bridge opens',
    () async {
      final registry = EditorSessionRegistry(
        gateways: _AgentGateway.new,
        commandIds: () => 'unused',
      );
      final container = ProviderContainer(
        overrides: [editorSessionRegistryProvider.overrideWithValue(registry)],
      );
      addTearDown(() async {
        container.dispose();
        await registry.closeAll();
      });

      expect(container.read(agentRunControllerProvider('tab')), isNull);

      await registry.open(tabId: 'tab', sourcePath: 'document.pdf');
      await Future<void>.delayed(Duration.zero);

      expect(container.read(agentRunControllerProvider('tab')), isNotNull);
    },
  );
}

class _AgentGateway implements EditorSessionGateway, EditorAgentGateway {
  final StreamController<EditorEvent> _events =
      StreamController<EditorEvent>.broadcast();

  @override
  Stream<EditorEvent> get events => _events.stream;

  @override
  AgentBridgeSession agentBridgeSession() => AgentBridgeSession.forTest(
    _NativePort(),
    sessionId: '00000000-0000-4000-8000-000000000001',
  );

  @override
  Future<EditorSessionMetadata> open(String sourcePath) async =>
      EditorSessionMetadata(
        schemaVersion: 1,
        sessionId: sourcePath,
        documentId: sourcePath,
        sourceFingerprint: sourcePath,
        revision: 0,
        pageCount: 0,
      );

  @override
  Future<void> close() => _events.close();

  @override
  Future<EditorCleanPatchAsset> cleanPatch(String objectId, int dpi) =>
      throw UnimplementedError();
  @override
  Future<EditorSceneObject> objectDetails(String objectId) =>
      throw UnimplementedError();
  @override
  Future<void> releaseCleanPatchMemory() async {}
  @override
  Future<EditorPageScene> requestPage(
    int pageNumber,
    int expectedRevision, {
    EditorViewportPriority priority = EditorViewportPriority.visible,
  }) => throw UnimplementedError();
  @override
  Future<EditorSaveResult> save(EditorSaveRequest request) =>
      throw UnimplementedError();
  @override
  Future<EditorCommandResult> submit(EditorCommandRequest request) =>
      throw UnimplementedError();
}

class _NativePort implements NativeAgentPort {
  @override
  Future<NativeAgentRunWire> approve(String runId, String approvalId) =>
      throw UnimplementedError();
  @override
  Future<void> cancel(String runId) async {}
  @override
  Stream<NativeAgentEventWire> events(String runId) =>
      const Stream<NativeAgentEventWire>.empty();
  @override
  Future<AgentConversationImportReceipt> importConversation(
    AgentConversationImport conversation,
  ) => throw UnimplementedError();
  @override
  Future<NativeAgentRunWire> rebase(
    String runId,
    String approvalId,
    int currentRevision,
  ) => throw UnimplementedError();
  @override
  Future<NativeAgentRunWire> reject(String runId, String approvalId) =>
      throw UnimplementedError();
  @override
  Future<AgentSelectionContext> selectionContext(AgentSelection selection) =>
      throw UnimplementedError();
  @override
  Future<NativeAgentRunWire> start(AgentStartRequest request) =>
      throw UnimplementedError();
}
