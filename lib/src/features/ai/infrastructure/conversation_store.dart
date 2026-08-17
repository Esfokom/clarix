import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crypto/crypto.dart';

import '../domain/conversation.dart';
import '../domain/ai_models.dart';

class ConversationStore {
  ConversationStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Database? _database;
  Directory? _root;

  Future<void> initialize() async {
    if (_database != null) {
      return;
    }
    sqfliteFfiInit();
    final Directory root = await _directoryProvider();
    await root.create(recursive: true);
    _root = root;
    _database = await databaseFactoryFfi.openDatabase(
      path.join(root.path, 'clarix_conversations.sqlite'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database db, int _) async {
          await db.execute(
            'CREATE TABLE conversations (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, title TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, summary TEXT, summary_through_sequence INTEGER)',
          );
          await db.execute(
            'CREATE TABLE conversation_messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, sequence INTEGER NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, citations_json TEXT NOT NULL, created_at TEXT NOT NULL, token_estimate INTEGER NOT NULL, is_compacted INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE INDEX conversations_document_updated ON conversations(document_id, updated_at DESC)',
          );
          await db.execute(
            'CREATE INDEX messages_conversation_sequence ON conversation_messages(conversation_id, sequence)',
          );
        },
      ),
    );
  }

  Future<List<ConversationThread>> listThreads(String documentId) async {
    final rows = await _db.query(
      'conversations',
      where: 'document_id = ?',
      whereArgs: <Object?>[documentId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_thread).toList(growable: false);
  }

  Future<bool> isMigrated(String documentId) async =>
      (await _migrationMarker(documentId)).exists();

  Future<void> markMigrated(String documentId) async {
    final file = await _migrationMarker(documentId);
    await file.writeAsString('native-conversation-v1\n', flush: true);
  }

  Future<File> _migrationMarker(String documentId) async {
    final root = _root;
    if (root == null) {
      throw StateError('ConversationStore.initialize() must be called first.');
    }
    final digest = sha256.convert(utf8.encode(documentId)).toString();
    return File(path.join(root.path, 'clarix_conversations.$digest.migrated'));
  }

  Future<ConversationThread> createThread({
    required String documentId,
    required String title,
  }) async {
    final now = DateTime.now().toUtc();
    final thread = ConversationThread(
      id: 'thread_${now.microsecondsSinceEpoch}',
      documentId: documentId,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('conversations', <String, Object?>{
      'id': thread.id,
      'document_id': documentId,
      'title': title,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return thread;
  }

  Future<void> deleteThread(String id) =>
      _db.delete('conversations', where: 'id = ?', whereArgs: <Object?>[id]);
  Future<void> clearAll() => _db.delete('conversations');

  Future<void> saveSummary({
    required String threadId,
    required String summary,
    required int throughSequence,
  }) => _db.transaction((Transaction transaction) async {
    await transaction.update(
      'conversations',
      <String, Object?>{
        'summary': summary,
        'summary_through_sequence': throughSequence,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[threadId],
    );
    await transaction.update(
      'conversation_messages',
      <String, Object?>{'is_compacted': 1},
      where: 'conversation_id = ? AND sequence <= ?',
      whereArgs: <Object?>[threadId, throughSequence],
    );
  });

  Future<List<ConversationMessage>> readMessages(String threadId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'conversation_messages',
      where: 'conversation_id = ?',
      whereArgs: <Object?>[threadId],
      orderBy: 'sequence ASC',
    );
    return rows.map(_message).toList(growable: false);
  }

  Future<void> appendExchange({
    required String threadId,
    required ConversationMessage user,
    required ConversationMessage assistant,
  }) => _db.transaction((Transaction transaction) async {
    final List<Map<String, Object?>> result = await transaction.rawQuery(
      'SELECT COALESCE(MAX(sequence), 0) AS value FROM conversation_messages '
      'WHERE conversation_id = ?',
      <Object?>[threadId],
    );
    final int start = (result.single['value'] as int?) ?? 0;
    await _insertMessage(transaction, threadId, user, start + 1);
    await _insertMessage(transaction, threadId, assistant, start + 2);
    await transaction.update(
      'conversations',
      <String, Object?>{'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: <Object?>[threadId],
    );
  });

  Database get _db {
    final Database? database = _database;
    if (database == null) {
      throw StateError('ConversationStore.initialize() must be called first.');
    }
    return database;
  }

  ConversationThread _thread(Map<String, Object?> row) => ConversationThread(
    id: row['id']! as String,
    documentId: row['document_id']! as String,
    title: row['title']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    summary: row['summary'] as String?,
    summaryThroughSequence: row['summary_through_sequence'] as int?,
  );

  Future<void> _insertMessage(
    Transaction transaction,
    String threadId,
    ConversationMessage message,
    int sequence,
  ) => transaction.insert('conversation_messages', <String, Object?>{
    'id': message.id,
    'conversation_id': threadId,
    'sequence': sequence,
    'role': message.role,
    'content': message.content,
    'citations_json': citationsJson(message.citations),
    'created_at': message.createdAt.toUtc().toIso8601String(),
    'token_estimate': message.tokenEstimate,
    'is_compacted': message.isCompacted ? 1 : 0,
  });

  ConversationMessage _message(Map<String, Object?> row) {
    final List<dynamic> rawCitations =
        jsonDecode(row['citations_json']! as String) as List<dynamic>;
    return ConversationMessage(
      id: row['id']! as String,
      role: row['role']! as String,
      content: row['content']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      tokenEstimate: row['token_estimate']! as int,
      citations: rawCitations
          .cast<Map<String, dynamic>>()
          .map(
            (Map<String, dynamic> item) => CitationSnippet(
              documentId: item['documentId']! as String,
              label: item['label']! as String,
              pageNumber: item['pageNumber']! as int,
              snippet: item['snippet']! as String,
            ),
          )
          .toList(growable: false),
      sequence: row['sequence']! as int,
      isCompacted: (row['is_compacted']! as int) == 1,
    );
  }

  static String citationsJson(List<CitationSnippet> citations) => jsonEncode(
    citations
        .map(
          (CitationSnippet item) => <String, Object?>{
            'documentId': item.documentId,
            'label': item.label,
            'pageNumber': item.pageNumber,
            'snippet': item.snippet,
          },
        )
        .toList(),
  );
}
