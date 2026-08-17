import '../../../core/agent/agent_bridge_types.dart';
import '../domain/conversation.dart';
import 'conversation_store.dart';

typedef NativeConversationImporter =
    Future<AgentConversationImportReceipt> Function(
      AgentConversationImport conversation,
    );

class NativeConversationMigrator {
  const NativeConversationMigrator({
    required this.legacy,
    required this.importConversation,
    required this.documentId,
  });

  final ConversationStore legacy;
  final NativeConversationImporter importConversation;
  final String documentId;

  Future<void> run() async {
    await legacy.initialize();
    if (await legacy.isMigrated(documentId)) return;
    final threads = await legacy.listThreads(documentId);
    for (final thread in threads) {
      final messages = await legacy.readMessages(thread.id);
      final receipt = await importConversation(
        AgentConversationImport(
          legacyId: thread.id,
          documentId: thread.documentId,
          title: thread.title,
          createdAt: thread.createdAt.toUtc().toIso8601String(),
          updatedAt: thread.updatedAt.toUtc().toIso8601String(),
          summary: thread.summary,
          summaryThroughSequence: thread.summaryThroughSequence,
          messages: messages.map(_message).toList(growable: false),
        ),
      );
      if (receipt.messageCount != messages.length ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(receipt.digestSha256)) {
        throw StateError('Native conversation import verification failed.');
      }
    }
    await legacy.markMigrated(documentId);
  }

  AgentConversationMessage _message(ConversationMessage message) =>
      AgentConversationMessage(
        id: message.id,
        sequence:
            message.sequence ??
            (throw StateError('Legacy conversation message has no sequence.')),
        role: message.role,
        content: message.content,
        citationsJson: ConversationStore.citationsJson(message.citations),
        createdAt: message.createdAt.toUtc().toIso8601String(),
        tokenEstimate: message.tokenEstimate,
        isCompacted: message.isCompacted,
      );
}
