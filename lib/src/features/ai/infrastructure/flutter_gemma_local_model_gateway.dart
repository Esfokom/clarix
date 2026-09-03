import 'package:flutter_gemma/flutter_gemma.dart';

import '../application/local_model_runtime.dart';
import '../domain/local_model_profile.dart';

/// Flutter Gemma owns model download, storage, and native LiteRT-LM handles.
/// This adapter is intentionally Dart-only; Rust remains responsible for RAG
/// and remote OpenAI-compatible provider streaming.
class FlutterGemmaLocalModelGateway implements LocalModelGateway {
  @override
  Future<bool> isInstalled(LocalModelProfile profile) =>
      FlutterGemma.isModelInstalled(profile.modelFileName);

  @override
  Future<void> install(LocalModelProfile profile) => FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  ).fromNetwork(profile.downloadUrl).install();

  @override
  Future<void> uninstall(LocalModelProfile profile) async {
    await FlutterGemma.uninstallModel(profile.modelFileName);
    await FlutterGemma.clearActiveInferenceIdentity();
  }

  @override
  Stream<String> generate({
    required LocalModelProfile profile,
    required String prompt,
    required String systemInstruction,
    required List<String> conversationHistory,
  }) async* {
    await install(profile);

    final model = await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: PreferredBackend.gpu,
      maxConcurrentSessions: 1,
    );
    final chat = await model.createChat(systemInstruction: systemInstruction);
    try {
      final String contextualPrompt = conversationHistory.isEmpty
          ? prompt
          : 'Previous conversation:\n${conversationHistory.join('\n')}\n\n'
                'Current user question: $prompt';
      await chat.addQueryChunk(
        Message.text(text: contextualPrompt, isUser: true),
      );
      await for (final response in chat.generateChatResponseAsync()) {
        if (response case TextResponse(:final token)) yield token;
      }
    } finally {
      await chat.close();
    }
  }
}
