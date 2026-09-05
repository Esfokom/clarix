import 'package:clarix/src/core/cancel_token.dart';
import 'package:clarix/src/features/ai/ai.dart';

import '../domain/study_models.dart';
import '../domain/study_schema.dart';
import 'study_budget.dart';
import 'study_source_planner.dart';

sealed class StudyRunProgress {
  const StudyRunProgress();
}

class StudyBatchStarted extends StudyRunProgress {
  const StudyBatchStarted({required this.index, required this.total});
  final int index;
  final int total;
}

class StudyBatchCompleted extends StudyRunProgress {
  const StudyBatchCompleted({
    required this.index,
    required this.total,
    required this.acceptedItems,
    required this.warnings,
  });
  final int index;
  final int total;
  final int acceptedItems;
  final List<String> warnings;
}

class StudyGenerationHarness {
  StudyGenerationHarness({required this.aiRuntimeService});

  final AiRuntimeService aiRuntimeService;

  final List<Flashcard> _cards = <Flashcard>[];
  final List<QuizQuestion> _questions = <QuizQuestion>[];
  final List<String> _warnings = <String>[];
  final Set<String> _seenNormalized = <String>{};

  List<Flashcard> get flashcards => List<Flashcard>.unmodifiable(_cards);
  List<QuizQuestion> get questions =>
      List<QuizQuestion>.unmodifiable(_questions);
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  Stream<StudyRunProgress> run({
    required StudyRunPlan plan,
    required StudyTarget target,
    required StudyGenerationConfig config,
    CancelToken? cancelToken,
  }) async* {
    final int total = plan.batches.length;
    for (int i = 0; i < total; i++) {
      if (cancelToken?.isCancelled ?? false) break;
      final StudyBatch batch = plan.batches[i];
      yield StudyBatchStarted(index: i, total: total);

      final String prompt = _buildPrompt(batch: batch, config: config);
      final List<CitationSnippet> documentSnippets = batch.chunks
          .map(
            (chunk) => CitationSnippet(
              documentId: chunk.documentId,
              label: chunk.sectionTitle ?? 'Page ${chunk.pageNumber}',
              pageNumber: chunk.pageNumber,
              snippet: chunk.text,
            ),
          )
          .toList(growable: false);

      String raw;
      try {
        final AiReply reply = await aiRuntimeService.sendPrompt(
          prompt: prompt,
          profileId: target.profileId,
          documentSnippets: documentSnippets,
          onToken: (String _) {},
        );
        raw = reply.text;
      } catch (error) {
        final String warning = 'Batch ${i + 1} failed: $error';
        _warnings.add(warning);
        yield StudyBatchCompleted(
          index: i,
          total: total,
          acceptedItems: 0,
          warnings: <String>[warning],
        );
        continue;
      }

      final List<String> batchWarnings = <String>[];
      int accepted = _tryCollect(raw, config, batchWarnings);
      if (accepted == 0 && batchWarnings.isNotEmpty) {
        try {
          final AiReply repaired = await aiRuntimeService.sendPrompt(
            prompt:
                'Your previous response could not be parsed as JSON. '
                'Return ONLY a JSON array matching the schema, with no '
                'prose before or after:\n\n$raw',
            profileId: target.profileId,
            documentSnippets: const <CitationSnippet>[],
            onToken: (String _) {},
          );
          batchWarnings.clear();
          accepted = _tryCollect(repaired.text, config, batchWarnings);
        } catch (error) {
          batchWarnings.add(
            'Batch ${i + 1} skipped after repair failed: $error',
          );
        }
      }
      _warnings.addAll(batchWarnings);
      yield StudyBatchCompleted(
        index: i,
        total: total,
        acceptedItems: accepted,
        warnings: batchWarnings,
      );
    }
  }

  int _tryCollect(
    String raw,
    StudyGenerationConfig config,
    List<String> warnings,
  ) {
    try {
      final ParsedBatch<Object> parsed = StudyJsonParser.parse(
        raw,
        config.kind,
      );
      warnings.addAll(parsed.warnings);
      int accepted = 0;
      if (config.kind == StudySetKind.flashcards) {
        for (final Flashcard card in parsed.items.cast<Flashcard>()) {
          if (_seenNormalized.add(_normalize(card.front))) {
            _cards.add(card);
            accepted++;
          }
        }
      } else {
        for (final QuizQuestion question
            in parsed.items.cast<QuizQuestion>()) {
          if (_seenNormalized.add(_normalize(question.prompt))) {
            _questions.add(question);
            accepted++;
          }
        }
      }
      return accepted;
    } on FormatException catch (error) {
      warnings.add('Could not parse model output: $error');
      return 0;
    }
  }

  String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _buildPrompt({
    required StudyBatch batch,
    required StudyGenerationConfig config,
  }) {
    final StringBuffer buffer = StringBuffer()
      ..writeln(studySchemaPrompt(config.kind))
      ..writeln('Difficulty: ${config.difficulty.name}')
      ..writeln(
        'Generate exactly ${batch.itemQuota} items from the supplied source text.',
      );
    if (config.focus != null) {
      buffer.writeln('Focus specifically on: ${config.focus}');
    }
    return buffer.toString();
  }
}
