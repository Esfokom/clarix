import 'dart:typed_data';

import 'ai_models.dart';

enum LiveConversationPhase {
  idle,
  connecting,
  listening,
  endingUserTurn,
  retrievingDocument,
  searchingWeb,
  speaking,
  interrupted,
  error,
  ended,
}

class LiveWebSource {
  const LiveWebSource({required this.title, required this.uri});
  final String title;
  final Uri uri;
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'uri': uri.toString(),
  };
  factory LiveWebSource.fromJson(Map<String, Object?> json) => LiveWebSource(
    title: json['title'] as String? ?? 'Web source',
    uri: Uri.parse(json['uri'] as String),
  );
}

class LiveConversationTurn {
  const LiveConversationTurn({
    required this.userText,
    required this.assistantText,
    this.citations = const <CitationSnippet>[],
    this.sources = const <LiveWebSource>[],
  });
  final String userText;
  final String assistantText;
  final List<CitationSnippet> citations;
  final List<LiveWebSource> sources;
}

class LiveConversationState {
  const LiveConversationState({
    required this.phase,
    this.status = 'Ready for voice conversation.',
    this.inputAmplitude = 0,
    this.userTranscript = '',
    this.assistantTranscript = '',
    this.completedTurns = const <LiveConversationTurn>[],
    this.errorMessage,
  });
  factory LiveConversationState.initial() =>
      const LiveConversationState(phase: LiveConversationPhase.idle);
  final LiveConversationPhase phase;
  final String status;
  final double inputAmplitude;
  final String userTranscript;
  final String assistantTranscript;
  final List<LiveConversationTurn> completedTurns;
  final String? errorMessage;
  LiveConversationState copyWith({
    LiveConversationPhase? phase,
    String? status,
    double? inputAmplitude,
    String? userTranscript,
    String? assistantTranscript,
    List<LiveConversationTurn>? completedTurns,
    String? errorMessage,
    bool clearError = false,
  }) => LiveConversationState(
    phase: phase ?? this.phase,
    status: status ?? this.status,
    inputAmplitude: inputAmplitude ?? this.inputAmplitude,
    userTranscript: userTranscript ?? this.userTranscript,
    assistantTranscript: assistantTranscript ?? this.assistantTranscript,
    completedTurns: completedTurns ?? this.completedTurns,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );
}

sealed class GeminiLiveEvent {
  const GeminiLiveEvent();
}

class GeminiLiveReadyEvent extends GeminiLiveEvent {
  const GeminiLiveReadyEvent();
}

class GeminiLiveActivityStartEvent extends GeminiLiveEvent {
  const GeminiLiveActivityStartEvent();
}

class GeminiLiveActivityEndEvent extends GeminiLiveEvent {
  const GeminiLiveActivityEndEvent();
}

class GeminiLiveAudioEvent extends GeminiLiveEvent {
  const GeminiLiveAudioEvent(this.bytes);
  final Uint8List bytes;
}

class GeminiLiveInputTranscriptEvent extends GeminiLiveEvent {
  const GeminiLiveInputTranscriptEvent(this.text, {this.isFinal = false});
  final String text;
  final bool isFinal;
}

class GeminiLiveOutputTranscriptEvent extends GeminiLiveEvent {
  const GeminiLiveOutputTranscriptEvent(this.text, {this.isFinal = false});
  final String text;
  final bool isFinal;
}

class GeminiLiveFunctionCallEvent extends GeminiLiveEvent {
  const GeminiLiveFunctionCallEvent({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

class GeminiLiveTurnCompleteEvent extends GeminiLiveEvent {
  const GeminiLiveTurnCompleteEvent();
}

class GeminiLiveErrorEvent extends GeminiLiveEvent {
  const GeminiLiveErrorEvent(this.message);
  final String message;
}
