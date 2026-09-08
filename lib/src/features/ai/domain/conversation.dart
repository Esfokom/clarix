import 'ai_models.dart';
import 'live_conversation.dart';

class ConversationThread {
  const ConversationThread({
    required this.id,
    required this.documentId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.summary,
    this.summaryThroughSequence,
  });

  final String id;
  final String documentId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? summary;
  final int? summaryThroughSequence;
}

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.tokenEstimate,
    required this.citations,
    this.sources = const <LiveWebSource>[],
    this.modelLabel,
    this.sequence,
    this.isCompacted = false,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final int tokenEstimate;
  final List<CitationSnippet> citations;
  final List<LiveWebSource> sources;
  final String? modelLabel;
  final int? sequence;
  final bool isCompacted;
}
