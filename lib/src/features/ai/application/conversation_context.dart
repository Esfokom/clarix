import '../domain/conversation.dart';

class ConversationContextPlan {
  const ConversationContextPlan({
    required this.estimatedTokens,
    required this.percentUsed,
    required this.messagesToCompact,
  });

  final int estimatedTokens;
  final int percentUsed;
  final List<ConversationMessage> messagesToCompact;
}

class ConversationContextPlanner {
  const ConversationContextPlanner({this.reservedCompletionTokens = 4096});

  final int reservedCompletionTokens;

  ConversationContextPlan plan({
    required List<ConversationMessage> messages,
    required int contextWindowTokens,
    String summary = '',
    String additionalContext = '',
  }) {
    final int budget = contextWindowTokens - reservedCompletionTokens;
    int used = _estimate(summary) + _estimate(additionalContext);
    for (final message in messages) {
      if (!message.isCompacted) used += message.tokenEstimate;
    }
    final List<ConversationMessage> compact = <ConversationMessage>[];
    for (final message in messages) {
      if (used <= budget || message.isCompacted) break;
      compact.add(message);
      used -= message.tokenEstimate;
    }
    return ConversationContextPlan(
      estimatedTokens: used + reservedCompletionTokens,
      percentUsed:
          ((used + reservedCompletionTokens) / contextWindowTokens * 100)
              .clamp(0, 100)
              .round(),
      messagesToCompact: compact,
    );
  }

  int _estimate(String text) => (text.trim().length / 4).ceil();
}
