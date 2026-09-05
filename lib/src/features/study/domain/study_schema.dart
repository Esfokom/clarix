import 'dart:convert';

import 'study_models.dart';

String studySchemaPrompt(StudySetKind kind) {
  switch (kind) {
    case StudySetKind.flashcards:
      return '''
Return ONLY a JSON array of flashcard objects, no prose before or after.
Each object has exactly these fields:
- "id": a short unique string id you invent, e.g. "c1"
- "front": a short question or prompt (string)
- "back": the answer (string)

Example:
[
  {"id": "c1", "front": "What is mitosis?", "back": "Cell division producing two identical daughter cells."}
]
''';
    case StudySetKind.quiz:
      return '''
Return ONLY a JSON array of quiz question objects, no prose before or after.
Each object has exactly these fields:
- "id": a short unique string id you invent, e.g. "q1"
- "prompt": the question text (string)
- "options": an array of exactly 4 distinct answer strings
- "correctIndex": the 0-based index into "options" of the correct answer (0-3)
- "explanation": a short explanation of why the correct answer is correct
- "difficulty": one of "easy", "medium", "hard"

Example:
[
  {"id": "q1", "prompt": "Which organelle produces ATP?", "options": ["Nucleus", "Mitochondria", "Ribosome", "Golgi"], "correctIndex": 1, "explanation": "Mitochondria are the site of ATP synthesis.", "difficulty": "medium"}
]
''';
  }
}

class ParsedBatch<T> {
  const ParsedBatch({
    required this.items,
    required this.dropped,
    required this.warnings,
  });

  final List<T> items;
  final int dropped;
  final List<String> warnings;
}

class StudyJsonParser {
  static ParsedBatch<Object> parse(String raw, StudySetKind kind) {
    final String jsonRegion = _extractJsonArray(raw);
    final dynamic decoded = jsonDecode(jsonRegion);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Expected a top-level JSON array.');
    }
    final List<Object> items = <Object>[];
    int dropped = 0;
    final List<String> warnings = <String>[];
    for (final dynamic entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        dropped++;
        continue;
      }
      try {
        items.add(
          kind == StudySetKind.flashcards
              ? Flashcard.fromJson(entry)
              : QuizQuestion.fromJson(entry),
        );
      } on ArgumentError catch (error) {
        dropped++;
        warnings.add('Dropped item: ${error.message}');
      } on TypeError catch (error) {
        dropped++;
        warnings.add('Dropped item: $error');
      }
    }
    return ParsedBatch<Object>(
      items: items,
      dropped: dropped,
      warnings: warnings,
    );
  }

  /// Strips Markdown code fences, then scans for the first balanced
  /// `[` ... `]` region so a prose preamble or trailing commentary does not
  /// fail the batch. Throws [FormatException] when no balanced region
  /// exists — that is the only case that fails an entire batch.
  static String _extractJsonArray(String raw) {
    String text = raw.trim();
    if (text.startsWith('```')) {
      final int firstNewline = text.indexOf('\n');
      if (firstNewline != -1) {
        text = text.substring(firstNewline + 1);
      }
      final int closingFence = text.lastIndexOf('```');
      if (closingFence != -1) {
        text = text.substring(0, closingFence);
      }
      text = text.trim();
    }

    final int start = text.indexOf('[');
    if (start == -1) {
      throw const FormatException('No JSON array found in model output.');
    }
    int depth = 0;
    for (int i = start; i < text.length; i++) {
      final String char = text[i];
      if (char == '[') depth++;
      if (char == ']') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    throw const FormatException(
      'No balanced JSON array found in model output.',
    );
  }
}
