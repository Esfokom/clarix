import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clarix_logger.dart';
import '../../../core/models.dart';
import '../domain/ai_feature_state.dart';
import '../domain/ai_models.dart';
import '../domain/ai_provider.dart';
import '../domain/conversation.dart';
import '../domain/local_model_profile.dart';
import 'ai_document_context.dart';
import 'ai_providers.dart';
import 'ai_runtime_service.dart';

/// Owns persisted AI preferences and the active document conversation.
///
/// Workspace supplies a document context at the call boundary; this controller
/// never reads workspace state or constructs editor sessions.
class AiNotifier extends AsyncNotifier<AiFeatureState> {
  String? _activeConversationId;

  @override
  Future<AiFeatureState> build() async {
    final preferences = ref.read(aiPreferencesStoreProvider);
    final profiles = ref.read(providerProfileStoreProvider);
    final saved = await preferences.readState();
    final available = await profiles.readProfiles();
    final localModels = await ref
        .read(localModelStoreProvider)
        .reconcile(
          supportedProfiles: <LocalModelProfile>[LocalModelProfile.gemma4E2b()],
          isInstalled: ref.read(localModelRuntimeProvider).isInstalled,
        );
    final defaultId = await profiles.readDefaultProfileId();
    final selectedRemote =
        _profileById(available, defaultId) ??
        (available.isEmpty ? null : available.first);
    final selectedLocal = localModels
        .where((LocalModelProfile item) => item.id == saved.selectedProviderId)
        .firstOrNull;
    final String? selectedId = selectedLocal?.id ?? selectedRemote?.id;
    final String? selectedLabel = selectedLocal?.label ?? selectedRemote?.label;
    final ready =
        selectedLocal != null ||
        (selectedRemote != null &&
            (await profiles.readApiKey(selectedRemote.id))?.isNotEmpty == true);
    return AiFeatureState(
      chat: saved.copyWith(
        chatBusy: false,
        selectedProviderId: selectedId,
        clearSelectedProviderId: selectedId == null,
        providerReady: ready,
        statusMessage: ready
            ? '$selectedLabel is ready.'
            : 'Add a provider to start a remote AI chat.',
      ),
      providerProfiles: available,
      localModels: localModels,
    );
  }

  Future<void> loadLatestConversation(String documentId) async {
    final store = await ref.read(conversationStoreProvider.future);
    final threads = await store.listThreads(documentId);
    if (threads.isEmpty) {
      _activeConversationId = null;
      await _commit(
        _current.copyWith(
          chat: _current.chat.copyWith(
            messages: const <ComposerMessage>[],
            lastRetrievalSnippets: const <CitationSnippet>[],
            clearActiveConversationId: true,
          ),
        ),
      );
      return;
    }
    await selectConversation(threads.first.id);
  }

  Future<void> selectConversation(String threadId) async {
    final store = await ref.read(conversationStoreProvider.future);
    final messages = await store.readMessages(threadId);
    _activeConversationId = threadId;
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          messages: messages
              .map(
                (message) => ComposerMessage(
                  id: message.id,
                  role: message.role,
                  text: message.content,
                  createdAt: message.createdAt,
                  citations: message.citations,
                  modelLabel: message.modelLabel,
                ),
              )
              .toList(growable: false),
          activeConversationId: threadId,
        ),
      ),
    );
  }

  Future<void> deleteConversation(String threadId, String documentId) async {
    await (await ref.read(
      conversationStoreProvider.future,
    )).deleteThread(threadId);
    if (_activeConversationId == threadId) _activeConversationId = null;
    await loadLatestConversation(documentId);
  }

  Future<void> startNewConversation() async {
    if (_current.chat.chatBusy) return;
    _activeConversationId = null;
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          messages: const <ComposerMessage>[],
          lastRetrievalSnippets: const <CitationSnippet>[],
          statusMessage: 'New conversation ready.',
          clearActiveConversationId: true,
        ),
      ),
    );
  }

  Future<void> clearAllConversations() async {
    await (await ref.read(conversationStoreProvider.future)).clearAll();
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          messages: const <ComposerMessage>[],
          lastRetrievalSnippets: const <CitationSnippet>[],
          statusMessage: 'All saved conversations were cleared.',
          clearActiveConversationId: true,
        ),
      ),
    );
  }

  Future<void> toggleScopeMode() => _commit(
    _current.copyWith(
      chat: _current.chat.copyWith(
        useCurrentDocumentScope: !_current.chat.useCurrentDocumentScope,
      ),
    ),
  );

  Future<void> selectProvider(String? profileId) async {
    final localModel = _current.localModels
        .where((LocalModelProfile item) => item.id == profileId)
        .firstOrNull;
    if (localModel != null) {
      await _commit(
        _current.copyWith(
          chat: _current.chat.copyWith(
            selectedProviderId: localModel.id,
            providerReady: true,
            statusMessage: '${localModel.label} is ready on this device.',
          ),
        ),
      );
      return;
    }
    final profile = _profileById(_current.providerProfiles, profileId);
    final profiles = ref.read(providerProfileStoreProvider);
    final ready =
        profile != null &&
        (await profiles.readApiKey(profile.id))?.isNotEmpty == true;
    if (profile != null) await profiles.saveDefaultProfileId(profile.id);
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          selectedProviderId: profile?.id,
          clearSelectedProviderId: profile == null,
          providerReady: ready,
          statusMessage: ready
              ? '${profile.label} is ready.'
              : 'Add an API key to use this provider.',
        ),
      ),
    );
  }

  Future<void> saveProvider(AiProviderProfile profile, {String? apiKey}) async {
    final profiles = ref.read(providerProfileStoreProvider);
    await profiles.saveProfile(
      profile,
      apiKey: apiKey?.trim().isEmpty == true ? null : apiKey?.trim(),
    );
    await _commit(
      _current.copyWith(providerProfiles: await profiles.readProfiles()),
    );
    await selectProvider(profile.id);
  }

  Future<void> downloadGemma4() async {
    final LocalModelProfile profile = LocalModelProfile.gemma4E2b();
    await ref.read(localModelRuntimeProvider).download(profile);
    final store = ref.read(localModelStoreProvider);
    await store.save(profile);
    await _commit(_current.copyWith(localModels: await store.readAll()));
    await selectProvider(profile.id);
  }

  Future<void> deleteLocalModel(LocalModelProfile profile) async {
    await ref.read(localModelRuntimeProvider).delete(profile);
    final store = ref.read(localModelStoreProvider);
    await store.delete(profile.id);
    final bool wasSelected = _current.chat.selectedProviderId == profile.id;
    await _commit(_current.copyWith(localModels: await store.readAll()));
    if (wasSelected) await selectProvider(null);
  }

  Future<void> testProvider(
    AiProviderProfile profile, {
    required String apiKey,
  }) => ref.read(aiRuntimeServiceProvider).testProvider(profile, apiKey);

  Future<void> deleteProvider(String profileId) async {
    final profiles = ref.read(providerProfileStoreProvider);
    await profiles.deleteProfile(profileId);
    final wasSelected = _current.chat.selectedProviderId == profileId;
    await _commit(
      _current.copyWith(providerProfiles: await profiles.readProfiles()),
    );
    if (wasSelected) {
      await selectProvider(null);
    }
  }

  Future<void> sendPrompt(String prompt, AiDocumentContext context) async {
    final current = _current;
    if (prompt.trim().isEmpty ||
        current.chat.chatBusy ||
        !current.chat.providerReady ||
        current.chat.selectedProviderId == null) {
      clarixLog.w(
        'AI prompt rejected: empty=${prompt.trim().isEmpty}, '
        'busy=${current.chat.chatBusy}, '
        'providerReady=${current.chat.providerReady}, '
        'providerSelected=${current.chat.selectedProviderId != null}.',
      );
      return;
    }
    clarixLog.i(
      'AI prompt accepted for document ${context.documentId} '
      'using provider ${current.chat.selectedProviderId}.',
    );
    final user = ComposerMessage(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      text: prompt.trim(),
      createdAt: DateTime.now().toUtc(),
      citations: const [],
    );
    final String modelLabel = _modelLabel(current.chat.selectedProviderId!);
    final assistant = ComposerMessage(
      id: 'assistant_${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      text: '',
      createdAt: DateTime.now().toUtc(),
      citations: const [],
      modelLabel: modelLabel,
    );
    await _commit(
      current.copyWith(
        chat: current.chat.copyWith(
          chatBusy: true,
          activityPhase: AiRuntimePhase.loadingInference,
          statusMessage:
              'Loading inference model. First response can take a minute.',
          messages: [...current.chat.messages, user, assistant],
          lastRetrievalSnippets: const [],
        ),
      ),
    );
    final buffer = StringBuffer();
    try {
      final List<CitationSnippet> snippets;
      if (current.chat.useCurrentDocumentScope && !context.isMissingFile) {
        _setActivity(
          AiRuntimePhase.retrieving,
          'Finding relevant PDF passages.',
        );
        final List<PdfChunkRecord> chunks = await ref
            .read(localRagServiceProvider)
            .retrieve(context.documentId, prompt.trim());
        snippets = chunks
            .map(
              (PdfChunkRecord chunk) => CitationSnippet(
                documentId: chunk.documentId,
                label: chunk.title,
                pageNumber: chunk.pageNumber,
                snippet: chunk.text,
              ),
            )
            .toList(growable: false);
      } else {
        snippets = const <CitationSnippet>[];
      }
      clarixLog.i(
        'RAG retrieved ${snippets.length} passage(s) for document '
        '${context.documentId} before local or remote inference.',
      );
      final store = await ref.read(conversationStoreProvider.future);
      final String threadId =
          _activeConversationId ??
          (await store.createThread(
            documentId: context.documentId,
            title: _conversationTitle(prompt),
          )).id;
      _activeConversationId = threadId;
      // Surface the thread the exchange is being written to, so the in-pane
      // history marks it as current the moment it is created.
      state = AsyncData(
        _current.copyWith(
          chat: _current.chat.copyWith(activeConversationId: threadId),
        ),
      );
      final List<RemoteChatMessage> history = current.chat.messages
          .map(
            (ComposerMessage message) =>
                RemoteChatMessage(role: message.role, content: message.text),
          )
          .toList(growable: false);
      clarixLog.i(
        'AI provider run starting with active thread $threadId and '
        '${history.length} prior message(s).',
      );
      final reply = await ref
          .read(aiRuntimeServiceProvider)
          .sendPrompt(
            prompt: prompt.trim(),
            profileId: current.chat.selectedProviderId!,
            documentSnippets: snippets,
            conversationHistory: history,
            onStatus: _setActivity,
            onToken: (token) {
              buffer.write(token);
              _replaceLastAssistant(buffer.toString(), busy: true);
            },
          );
      _replaceLastAssistant(
        reply.text,
        citations: snippets,
        busy: false,
        phase: AiRuntimePhase.idle,
        status: 'Ready to chat with your remote provider.',
        modelLabel: modelLabel,
      );
      await store.appendExchange(
        threadId: threadId,
        user: _conversationMessage(user),
        assistant: _conversationMessage(
          assistant.copyWith(
            text: reply.text,
            citations: snippets,
            modelLabel: modelLabel,
          ),
        ),
      );
    } catch (error, stackTrace) {
      clarixLog.w(
        'Prompt generation failed.',
        error: error,
        stackTrace: stackTrace,
      );
      _replaceLastAssistant(
        'I could not generate a response.\n\n$error',
        busy: false,
        phase: AiRuntimePhase.failed,
        status: 'Generation failed.',
        modelLabel: modelLabel,
      );
    }
  }

  Future<void> stopGeneration() async {
    await ref.read(aiRuntimeServiceProvider).stopGeneration();
    await _commit(
      _current.copyWith(
        chat: _current.chat.copyWith(
          chatBusy: false,
          activityPhase: AiRuntimePhase.idle,
          statusMessage: 'Generation stopped.',
        ),
      ),
    );
  }

  AiFeatureState get _current => state.value ?? AiFeatureState.initial();
  Future<void> _commit(AiFeatureState value) async {
    state = AsyncData(value);
    await ref.read(aiPreferencesStoreProvider).writeState(value.chat);
  }

  void _setActivity(AiRuntimePhase phase, String message) {
    final value = _current;
    state = AsyncData(
      value.copyWith(
        chat: value.chat.copyWith(activityPhase: phase, statusMessage: message),
      ),
    );
    clarixLog.i('AI activity: ${phase.name} - $message');
  }

  void _replaceLastAssistant(
    String text, {
    List<CitationSnippet>? citations,
    bool? busy,
    AiRuntimePhase? phase,
    String? status,
    String? modelLabel,
  }) {
    final value = _current;
    if (value.chat.messages.isEmpty) return;
    final messages = List<ComposerMessage>.from(value.chat.messages);
    messages[messages.length - 1] = messages.last.copyWith(
      text: text,
      citations: citations,
      modelLabel: modelLabel,
    );
    state = AsyncData(
      value.copyWith(
        chat: value.chat.copyWith(
          messages: messages,
          chatBusy: busy,
          activityPhase: phase,
          statusMessage: status,
          lastRetrievalSnippets: citations,
        ),
      ),
    );
  }

  AiProviderProfile? _profileById(
    List<AiProviderProfile> profiles,
    String? id,
  ) => id == null
      ? null
      : profiles.where((profile) => profile.id == id).firstOrNull;

  String _modelLabel(String id) =>
      _current.localModels
          .where((LocalModelProfile item) => item.id == id)
          .firstOrNull
          ?.label ??
      _current.providerProfiles
          .where((AiProviderProfile item) => item.id == id)
          .firstOrNull
          ?.label ??
      id;

  String _conversationTitle(String prompt) {
    final String normalized = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= 52
        ? normalized
        : '${normalized.substring(0, 49)}...';
  }

  ConversationMessage _conversationMessage(ComposerMessage message) =>
      ConversationMessage(
        id: message.id,
        role: message.role,
        content: message.text,
        createdAt: message.createdAt,
        tokenEstimate: (message.text.trim().length / 4).ceil(),
        citations: message.citations,
        modelLabel: message.modelLabel,
      );
}
