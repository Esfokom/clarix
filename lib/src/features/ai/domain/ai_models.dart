import 'dart:convert';

enum AiRuntimePhase {
  idle,
  restoringInference,
  restoringEmbedding,
  loadingInference,
  preparingGrounding,
  indexing,
  validatingProvider,
  retrieving,
  callingProvider,
  executingTool,
  generating,
  cancelled,
  failed,
}

class AiWorkspaceState {
  const AiWorkspaceState({
    required this.providerReady,
    required this.selectedProviderId,
    required this.chatBusy,
    required this.activityPhase,
    required this.statusMessage,
    required this.messages,
    required this.useCurrentDocumentScope,
    required this.lastRetrievalSnippets,
  });

  final bool providerReady;
  final String? selectedProviderId;
  final bool chatBusy;
  final AiRuntimePhase activityPhase;
  final String statusMessage;
  final List<ComposerMessage> messages;
  final bool useCurrentDocumentScope;
  final List<CitationSnippet> lastRetrievalSnippets;

  factory AiWorkspaceState.initial() => const AiWorkspaceState(
    providerReady: false,
    selectedProviderId: null,
    chatBusy: false,
    activityPhase: AiRuntimePhase.idle,
    statusMessage: 'Add a provider to start a remote AI chat.',
    messages: <ComposerMessage>[],
    useCurrentDocumentScope: true,
    lastRetrievalSnippets: <CitationSnippet>[],
  );

  AiWorkspaceState copyWith({
    bool? providerReady,
    String? selectedProviderId,
    bool clearSelectedProviderId = false,
    bool? chatBusy,
    AiRuntimePhase? activityPhase,
    String? statusMessage,
    List<ComposerMessage>? messages,
    bool? useCurrentDocumentScope,
    List<CitationSnippet>? lastRetrievalSnippets,
  }) {
    return AiWorkspaceState(
      providerReady: providerReady ?? this.providerReady,
      selectedProviderId: clearSelectedProviderId
          ? null
          : selectedProviderId ?? this.selectedProviderId,
      chatBusy: chatBusy ?? this.chatBusy,
      activityPhase: activityPhase ?? this.activityPhase,
      statusMessage: statusMessage ?? this.statusMessage,
      messages: messages ?? this.messages,
      useCurrentDocumentScope:
          useCurrentDocumentScope ?? this.useCurrentDocumentScope,
      lastRetrievalSnippets:
          lastRetrievalSnippets ?? this.lastRetrievalSnippets,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'providerReady': providerReady,
    'selectedProviderId': selectedProviderId,
    'activityPhase': activityPhase.name,
    'statusMessage': statusMessage,
    'useCurrentDocumentScope': useCurrentDocumentScope,
  };

  factory AiWorkspaceState.fromJson(Map<String, dynamic> json) {
    return AiWorkspaceState.initial().copyWith(
      providerReady: json['providerReady'] as bool? ?? false,
      selectedProviderId: json['selectedProviderId'] as String?,
      activityPhase: AiRuntimePhase.idle,
      statusMessage: json['selectedProviderId'] == null
          ? 'Add a provider to start a remote AI chat.'
          : json['statusMessage'] as String?,
      useCurrentDocumentScope: json['useCurrentDocumentScope'] as bool? ?? true,
    );
  }
}

class ComposerMessage {
  const ComposerMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    required this.citations,
  });

  final String id;
  final String role;
  final String text;
  final DateTime createdAt;
  final List<CitationSnippet> citations;

  bool get isUser => role == 'user';

  ComposerMessage copyWith({String? text, List<CitationSnippet>? citations}) {
    return ComposerMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      citations: citations ?? this.citations,
    );
  }
}

class CitationSnippet {
  const CitationSnippet({
    required this.documentId,
    required this.label,
    required this.pageNumber,
    required this.snippet,
  });

  final String documentId;
  final String label;
  final int pageNumber;
  final String snippet;

  factory CitationSnippet.fromMetadata({
    required String content,
    required Object? metadata,
  }) {
    Map<String, dynamic> decoded = const <String, dynamic>{};
    if (metadata is String && metadata.isNotEmpty) {
      final dynamic parsed = jsonDecode(metadata);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } else if (metadata is Map<String, dynamic>) {
      decoded = metadata;
    }

    return CitationSnippet(
      documentId: decoded['documentId'] as String? ?? 'unknown-document',
      label: decoded['title'] as String? ?? 'PDF context',
      pageNumber: decoded['pageNumber'] as int? ?? 1,
      snippet: content,
    );
  }
}
