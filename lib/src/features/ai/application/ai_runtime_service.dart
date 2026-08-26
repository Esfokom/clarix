import 'dart:async';

import '../../../core/agent/agent_bridge_types.dart';
import '../../../core/clarix_logger.dart';
import '../../../core/ffi/agent_api.dart' as native_agent;
import '../domain/ai_models.dart';
import '../domain/ai_provider.dart';
import '../infrastructure/provider_profile_store.dart';
import 'agent_run_controller.dart';

class AiRuntimeService {
  AiRuntimeService({required this.providerProfiles});

  final ProviderProfileStore providerProfiles;
  AgentRunController? _activeController;

  Future<void> testProvider(AiProviderProfile profile, String apiKey) {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('Enter an API key before testing this provider.');
    }
    return native_agent.testAgentProvider(
      request: native_agent.NativeProviderTestRequest(
        providerEndpoint: profile.baseUrl,
        modelId: profile.modelId,
        headers: profile.headers,
        apiKey: apiKey.trim(),
      ),
    );
  }

  Future<AiReply> sendPrompt({
    required String prompt,
    required String profileId,
    required String conversationId,
    required AgentRunController controller,
    required void Function(String token) onToken,
    void Function(AiRuntimePhase phase, String message)? onStatus,
  }) async {
    final profiles = await providerProfiles.readProfiles();
    final profile = profiles.where((item) => item.id == profileId).firstOrNull;
    if (profile == null) {
      clarixLog.w('AI runtime rejected prompt: selected provider is missing.');
      throw StateError('Select a remote AI provider to chat.');
    }
    final key = await providerProfiles.readApiKey(profile.id);
    if (key == null || key.isEmpty) {
      clarixLog.w(
        'AI runtime rejected prompt: ${profile.label} has no API key.',
      );
      throw StateError('Add an API key for ${profile.label}.');
    }
    clarixLog.i(
      'AI runtime prepared ${profile.label} streaming request '
      '(model=${profile.modelId}, endpoint=${profile.baseUrl}).',
    );
    _activeController = controller;
    var delivered = 0;
    final terminal = Completer<AgentRunControllerState>();
    late final StreamSubscription<AgentRunControllerState> subscription;
    subscription = controller.changes.listen(
      (state) {
        if (state.assistantText.length > delivered) {
          onToken(state.assistantText.substring(delivered));
          delivered = state.assistantText.length;
        }
        onStatus?.call(_phase(state.status), state.progressLabel);
        if ((state.status?.isTerminal ?? false) && !terminal.isCompleted) {
          terminal.complete(state);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!terminal.isCompleted) terminal.completeError(error, stack);
      },
    );
    try {
      onStatus?.call(AiRuntimePhase.generating, 'Contacting ${profile.label}.');
      clarixLog.i('AI native agent run start requested.');
      await controller.start(
        AgentStartRequest(
          providerEndpoint: profile.baseUrl,
          modelId: profile.modelId,
          headers: profile.headers,
          apiKey: key,
          conversationId: conversationId,
          userPrompt: prompt,
        ),
      );
      final result = await terminal.future;
      clarixLog.i(
        'AI native agent run reached ${result.status?.name ?? 'unknown'} status.',
      );
      if (result.error != null || result.status == AgentRunStatus.failed) {
        throw StateError(
          'Native agent run failed: ${result.error ?? 'provider error'}',
        );
      }
      return AiReply(
        text: result.assistantText,
        citations: const <CitationSnippet>[],
      );
    } finally {
      await subscription.cancel();
      if (identical(_activeController, controller)) _activeController = null;
    }
  }

  Future<void> stopGeneration() async => _activeController?.cancel();
  Future<void> dispose() async => stopGeneration();

  AiRuntimePhase _phase(AgentRunStatus? status) => switch (status) {
    AgentRunStatus.callingProvider => AiRuntimePhase.generating,
    AgentRunStatus.executingTool => AiRuntimePhase.executingTool,
    AgentRunStatus.failed => AiRuntimePhase.failed,
    _ => AiRuntimePhase.loadingInference,
  };
}

class AiReply {
  const AiReply({required this.text, required this.citations});
  final String text;
  final List<CitationSnippet> citations;
}
