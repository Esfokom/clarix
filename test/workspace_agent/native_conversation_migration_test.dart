import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/core/agent/agent_bridge_types.dart';
import 'package:clarix/src/features/workspace/domain/conversation.dart';
import 'package:clarix/src/features/workspace/infrastructure/conversation_store.dart';
import 'package:clarix/src/features/workspace/infrastructure/native_conversation_migrator.dart';

void main() {
  test(
    'legacy conversations import once with stable IDs and ordering',
    () async {
      final root = await Directory.systemTemp.createTemp('clarix-migration-');
      final store = ConversationStore(directoryProvider: () async => root);
      await store.initialize();
      final thread = await store.createThread(
        documentId: 'legacy-doc',
        title: 'Draft',
      );
      await store.appendExchange(
        threadId: thread.id,
        user: _message('u1', 'user', 'Hello'),
        assistant: _message('a1', 'assistant', 'Hi'),
      );
      final imports = <AgentConversationImport>[];
      final migrator = NativeConversationMigrator(
        legacy: store,
        documentId: 'legacy-doc',
        importConversation: (value) async {
          imports.add(value);
          return AgentConversationImportReceipt(
            conversationId: '00000000-0000-4000-8000-000000000010',
            messageCount: value.messages.length,
            digestSha256: List<String>.filled(64, '0').join(),
            alreadyPresent: false,
          );
        },
      );
      await migrator.run();
      await migrator.run();
      expect(imports, hasLength(1));
      expect(imports.single.legacyId, thread.id);
      expect(imports.single.messages.map((message) => message.sequence), <int>[
        1,
        2,
      ]);
    },
  );

  test('failed import preserves legacy data and retries', () async {
    final root = await Directory.systemTemp.createTemp(
      'clarix-migration-retry-',
    );
    final store = ConversationStore(directoryProvider: () async => root);
    await store.initialize();
    final thread = await store.createThread(
      documentId: 'legacy-doc',
      title: 'Draft',
    );
    await store.appendExchange(
      threadId: thread.id,
      user: _message('u1', 'user', 'Hello'),
      assistant: _message('a1', 'assistant', 'Hi'),
    );
    var attempts = 0;
    final migrator = NativeConversationMigrator(
      legacy: store,
      documentId: 'legacy-doc',
      importConversation: (value) async {
        attempts++;
        if (attempts == 1) throw StateError('fixture failure');
        return AgentConversationImportReceipt(
          conversationId: '00000000-0000-4000-8000-000000000010',
          messageCount: value.messages.length,
          digestSha256: List<String>.filled(64, '1').join(),
          alreadyPresent: false,
        );
      },
    );
    await expectLater(migrator.run(), throwsStateError);
    expect(await store.readMessages(thread.id), hasLength(2));
    expect(await store.isMigrated('legacy-doc'), isFalse);
    await migrator.run();
    expect(attempts, 2);
    expect(await store.isMigrated('legacy-doc'), isTrue);
  });
}

ConversationMessage _message(String id, String role, String content) =>
    ConversationMessage(
      id: id,
      role: role,
      content: content,
      createdAt: DateTime.utc(2026, 8, 17),
      tokenEstimate: 2,
      citations: const [],
    );
