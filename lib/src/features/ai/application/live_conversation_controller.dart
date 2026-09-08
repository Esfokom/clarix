import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/clarix_logger.dart';
import '../domain/live_conversation.dart';
import '../infrastructure/gemini_live_gateway.dart';
import '../infrastructure/live_audio_adapter.dart';
import '../infrastructure/conversation_store.dart';
import '../domain/conversation.dart';
import 'ai_document_context.dart';
import 'live_document_tool.dart';

class LiveConversationController extends ChangeNotifier {
  LiveConversationController({
    required GeminiLiveGateway gateway,
    required LiveAudioAdapter audio,
    required ActiveDocumentTool documentTool,
    required String apiKey,
    required Future<ConversationStore> conversationStore,
  }) : _gateway = gateway,
       _audio = audio,
       _documentTool = documentTool,
       _apiKey = apiKey,
       _conversationStore = conversationStore;
  final GeminiLiveGateway _gateway;
  final LiveAudioAdapter _audio;
  final ActiveDocumentTool _documentTool;
  final String _apiKey;
  final Future<ConversationStore> _conversationStore;
  String? _threadId;
  LiveConversationState _state = LiveConversationState.initial();
  LiveConversationState get state => _state;
  set state(LiveConversationState value) {
    _state = value;
    notifyListeners();
  }

  GeminiLiveSession? _session;
  StreamSubscription? _events;
  StreamSubscription? _audioInput;
  StreamSubscription? _level;
  AiDocumentContext? _context;
  final List _citations = <dynamic>[];
  Future<void> start(AiDocumentContext context) async {
    clarixLog.i('Live conversation start requested for ${context.documentId}.');
    if (_apiKey.trim().isEmpty) {
      state = state.copyWith(
        phase: LiveConversationPhase.error,
        errorMessage:
            'Voice conversation is unavailable. Start Clarix with GEMINI_API_KEY.',
      );
      return;
    }
    state = state.copyWith(
      phase: LiveConversationPhase.connecting,
      status: 'Connecting…',
      clearError: true,
    );
    if (!await _audio.requestPermission()) {
      clarixLog.w('Live conversation microphone permission denied.');
      state = state.copyWith(
        phase: LiveConversationPhase.error,
        errorMessage: 'Microphone permission was not granted.',
      );
      return;
    }
    try {
      _context = context;
      _session = await _gateway.connect(
        configuration: GeminiLiveConfiguration(
          apiKey: _apiKey,
          documentTitle: context.title,
        ),
      );
      _events = _session!.events.listen(_onEvent);
      await _audio.startCapture();
      clarixLog.i('Live conversation microphone stream started.');
      _audioInput = _audio.inputPcm16.listen((b) => _session?.sendAudio(b));
      _level = _audio.inputLevel.listen(
        (v) => state = state.copyWith(inputAmplitude: v),
      );
    } catch (error, stackTrace) {
      clarixLog.w(
        'Live conversation startup failed.',
        error: error,
        stackTrace: stackTrace,
      );
      await _teardown();
      state = state.copyWith(
        phase: LiveConversationPhase.error,
        errorMessage: 'Could not start the voice conversation. Try again.',
      );
    }
  }

  Future<void> _onEvent(GeminiLiveEvent event) async {
    switch (event) {
      case GeminiLiveReadyEvent():
        clarixLog.i('Live conversation is ready for speech.');
        state = state.copyWith(
          phase: LiveConversationPhase.listening,
          status: 'Listening',
        );
      case GeminiLiveActivityStartEvent():
        await _audio.stopOutput();
        state = state.copyWith(
          phase: LiveConversationPhase.listening,
          status: 'Listening',
        );
      case GeminiLiveAudioEvent(:final bytes):
        await _audio.enqueueOutputPcm24(bytes);
        state = state.copyWith(
          phase: LiveConversationPhase.speaking,
          status: 'Speaking',
        );
      case GeminiLiveInputTranscriptEvent(:final text):
        state = state.copyWith(userTranscript: '${state.userTranscript}$text');
      case GeminiLiveOutputTranscriptEvent(:final text):
        state = state.copyWith(
          assistantTranscript: '${state.assistantTranscript}$text',
        );
      case GeminiLiveFunctionCallEvent(
        :final id,
        :final name,
        :final arguments,
      ):
        clarixLog.i('Gemini Live requested tool $name.');
        await _tool(id, name, arguments);
      case GeminiLiveTurnCompleteEvent():
        await _persistTurn();
        state = state.copyWith(
          phase: LiveConversationPhase.listening,
          status: 'Listening',
        );
      case GeminiLiveErrorEvent(:final message):
        state = state.copyWith(
          phase: LiveConversationPhase.error,
          errorMessage: message,
        );
      case GeminiLiveActivityEndEvent():
        state = state.copyWith(
          phase: LiveConversationPhase.endingUserTurn,
          status: 'Finishing your turn…',
        );
    }
  }

  Future<void> _persistTurn() async {
    if (_context == null ||
        state.userTranscript.trim().isEmpty ||
        state.assistantTranscript.trim().isEmpty) {
      return;
    }
    final store = await _conversationStore;
    final titleText = state.userTranscript.trim();
    final thread = _threadId == null
        ? await store.createThread(
            documentId: _context!.documentId,
            title: titleText.length <= 52
                ? titleText
                : titleText.substring(0, 52),
          )
        : null;
    _threadId ??= thread?.id;
    final now = DateTime.now().toUtc();
    await store.appendExchange(
      threadId: _threadId!,
      user: ConversationMessage(
        id: 'live_user_${now.microsecondsSinceEpoch}',
        role: 'user',
        content: state.userTranscript.trim(),
        createdAt: now,
        tokenEstimate: (state.userTranscript.length / 4).ceil(),
        citations: const [],
      ),
      assistant: ConversationMessage(
        id: 'live_assistant_${now.microsecondsSinceEpoch}',
        role: 'assistant',
        content: state.assistantTranscript.trim(),
        createdAt: now,
        tokenEstimate: (state.assistantTranscript.length / 4).ceil(),
        citations: _citations.cast(),
        modelLabel: 'Gemini 3.1 Flash Live',
      ),
    );
  }

  Future<void> _tool(String id, String name, Map<String, Object?> args) async {
    if (name != 'query_active_document' || _context == null) {
      await _session?.sendToolResponse(
        id: id,
        name: name,
        response: <String, Object?>{'status': 'unsupported_function'},
      );
      return;
    }
    state = state.copyWith(
      phase: LiveConversationPhase.retrievingDocument,
      status: 'Finding relevant passages…',
    );
    final result = await _documentTool.execute(
      context: _context!,
      query: args['query'] as String? ?? '',
    );
    _citations.addAll(result.citations);
    await _session?.sendToolResponse(
      id: id,
      name: name,
      response: result.response,
    );
  }

  Future<void> end({String reason = 'Voice conversation ended.'}) async {
    clarixLog.i('Live conversation ending: $reason');
    await _teardown();
    state = state.copyWith(phase: LiveConversationPhase.ended, status: reason);
  }

  Future<void> _teardown() async {
    await _events?.cancel();
    await _audioInput?.cancel();
    await _level?.cancel();
    await _audio.stop();
    await _session?.close();
    _events = null;
    _audioInput = null;
    _level = null;
    _session = null;
  }

  @override
  void dispose() {
    unawaited(_teardown());
    unawaited(_audio.dispose());
    super.dispose();
  }
}
