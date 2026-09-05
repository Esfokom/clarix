import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/study_models.dart';

class StudyStore {
  StudyStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Database? _database;

  Future<void> initialize() async {
    if (_database != null) return;
    sqfliteFfiInit();
    final Directory root = await _directoryProvider();
    await root.create(recursive: true);
    _database = await databaseFactoryFfi.openDatabase(
      path.join(root.path, 'clarix_study.sqlite'),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (Database db, int _) async {
          await db.execute(
            'CREATE TABLE study_sets (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL, created_at TEXT NOT NULL, model_label TEXT, generated_on_device INTEGER NOT NULL, config_json TEXT NOT NULL, is_partial INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE TABLE flashcards (id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE, position INTEGER NOT NULL, front TEXT NOT NULL, back TEXT NOT NULL, page_number INTEGER, section_title TEXT)',
          );
          await db.execute(
            'CREATE TABLE quiz_questions (id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE, position INTEGER NOT NULL, prompt TEXT NOT NULL, options_json TEXT NOT NULL, correct_index INTEGER NOT NULL, explanation TEXT NOT NULL, page_number INTEGER, difficulty TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE quiz_attempts (id TEXT PRIMARY KEY, set_id TEXT NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE, started_at TEXT NOT NULL, completed_at TEXT, answers_json TEXT NOT NULL, correct_count INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX study_sets_document_created ON study_sets(document_id, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX flashcards_set_position ON flashcards(set_id, position)',
          );
          await db.execute(
            'CREATE INDEX quiz_questions_set_position ON quiz_questions(set_id, position)',
          );
          await db.execute(
            'CREATE INDEX quiz_attempts_set_started ON quiz_attempts(set_id, started_at DESC)',
          );
        },
      ),
    );
  }

  Future<void> saveStudySet(StudySet set) =>
      _db.transaction((Transaction tx) async {
        await tx.insert('study_sets', <String, Object?>{
          'id': set.id,
          'document_id': set.documentId,
          'kind': set.kind.name,
          'title': set.title,
          'created_at': set.createdAt.toUtc().toIso8601String(),
          'model_label': set.modelLabel,
          'generated_on_device': set.generatedOnDevice ? 1 : 0,
          'config_json': jsonEncode(set.config.toJson()),
          'is_partial': set.isPartial ? 1 : 0,
        });
        for (int i = 0; i < set.cards.length; i++) {
          final Flashcard card = set.cards[i];
          await tx.insert('flashcards', <String, Object?>{
            'id': card.id,
            'set_id': set.id,
            'position': i,
            'front': card.front,
            'back': card.back,
            'page_number': card.pageNumber,
            'section_title': card.sectionTitle,
          });
        }
        for (int i = 0; i < set.questions.length; i++) {
          final QuizQuestion question = set.questions[i];
          await tx.insert('quiz_questions', <String, Object?>{
            'id': question.id,
            'set_id': set.id,
            'position': i,
            'prompt': question.prompt,
            'options_json': jsonEncode(question.options),
            'correct_index': question.correctIndex,
            'explanation': question.explanation,
            'page_number': question.pageNumber,
            'difficulty': question.difficulty.name,
          });
        }
      });

  Future<List<StudySet>> listSets(String documentId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'study_sets',
      where: 'document_id = ?',
      whereArgs: <Object?>[documentId],
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map((Map<String, Object?> row) => _hydrate(row)));
  }

  Future<StudySet?> readSet(String setId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'study_sets',
      where: 'id = ?',
      whereArgs: <Object?>[setId],
    );
    if (rows.isEmpty) return null;
    return _hydrate(rows.single);
  }

  Future<void> deleteSet(String setId) =>
      _db.delete('study_sets', where: 'id = ?', whereArgs: <Object?>[setId]);

  Future<void> saveAttempt(QuizAttempt attempt) =>
      _db.insert('quiz_attempts', <String, Object?>{
        'id': attempt.id,
        'set_id': attempt.setId,
        'started_at': attempt.startedAt.toUtc().toIso8601String(),
        'completed_at': attempt.completedAt?.toUtc().toIso8601String(),
        'answers_json': jsonEncode(attempt.answers),
        'correct_count': attempt.correctCount,
      });

  Future<QuizAttempt?> latestAttempt(String setId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'quiz_attempts',
      where: 'set_id = ?',
      whereArgs: <Object?>[setId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.single;
    return QuizAttempt(
      id: row['id']! as String,
      setId: row['set_id']! as String,
      startedAt: DateTime.parse(row['started_at']! as String),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at']! as String),
      answers:
          (jsonDecode(row['answers_json']! as String) as Map<String, dynamic>)
              .map((String k, dynamic v) => MapEntry<String, int>(k, v as int)),
      correctCount: row['correct_count']! as int,
    );
  }

  Future<void> close() async {
    final Database? database = _database;
    _database = null;
    if (database != null) await database.close();
  }

  Future<StudySet> _hydrate(Map<String, Object?> row) async {
    final String setId = row['id']! as String;
    final List<Map<String, Object?>> cardRows = await _db.query(
      'flashcards',
      where: 'set_id = ?',
      whereArgs: <Object?>[setId],
      orderBy: 'position ASC',
    );
    final List<Map<String, Object?>> questionRows = await _db.query(
      'quiz_questions',
      where: 'set_id = ?',
      whereArgs: <Object?>[setId],
      orderBy: 'position ASC',
    );
    return StudySet(
      id: setId,
      documentId: row['document_id']! as String,
      kind: StudySetKind.values.byName(row['kind']! as String),
      title: row['title']! as String,
      createdAt: DateTime.parse(row['created_at']! as String),
      modelLabel: row['model_label'] as String?,
      generatedOnDevice: (row['generated_on_device']! as int) == 1,
      config: StudyGenerationConfig.fromJson(
        jsonDecode(row['config_json']! as String) as Map<String, dynamic>,
      ),
      isPartial: (row['is_partial']! as int) == 1,
      cards: cardRows
          .map(
            (Map<String, Object?> r) => Flashcard(
              id: r['id']! as String,
              front: r['front']! as String,
              back: r['back']! as String,
              pageNumber: r['page_number'] as int?,
              sectionTitle: r['section_title'] as String?,
            ),
          )
          .toList(growable: false),
      questions: questionRows
          .map(
            (Map<String, Object?> r) => QuizQuestion(
              id: r['id']! as String,
              prompt: r['prompt']! as String,
              options: (jsonDecode(r['options_json']! as String) as List<dynamic>)
                  .cast<String>(),
              correctIndex: r['correct_index']! as int,
              explanation: r['explanation']! as String,
              pageNumber: r['page_number'] as int?,
              difficulty: StudyDifficulty.values.byName(
                r['difficulty']! as String,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Database get _db {
    final Database? database = _database;
    if (database == null) {
      throw StateError('StudyStore.initialize() must be called first.');
    }
    return database;
  }
}
