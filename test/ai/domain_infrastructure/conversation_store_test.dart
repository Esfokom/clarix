import 'dart:io';

import 'package:clarix/src/features/ai/domain/conversation.dart';
import 'package:clarix/src/features/ai/infrastructure/conversation_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ConversationStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('clarix-conversations-test');
    store = ConversationStore(directoryProvider: () async => root);
    await store.initialize();
  });

  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test(
    'persists an exchange with the responding model for later follow-ups',
    () async {
      final thread = await store.createThread(
        documentId: 'document-1',
        title: 'First question',
      );
      final now = DateTime.utc(2026, 9, 3);

      await store.appendExchange(
        threadId: thread.id,
        user: ConversationMessage(
          id: 'user-1',
          role: 'user',
          content: 'What is the conclusion?',
          createdAt: now,
          tokenEstimate: 6,
          citations: const [],
        ),
        assistant: ConversationMessage(
          id: 'assistant-1',
          role: 'assistant',
          content: 'The conclusion is positive.',
          createdAt: now,
          tokenEstimate: 7,
          citations: const [],
          modelLabel: 'Gemma 4 E2B (Local)',
        ),
      );

      final messages = await store.readMessages(thread.id);

      expect(messages.map((ConversationMessage item) => item.content), <String>[
        'What is the conclusion?',
        'The conclusion is positive.',
      ]);
      expect(messages.last.modelLabel, 'Gemma 4 E2B (Local)');
    },
  );
}
