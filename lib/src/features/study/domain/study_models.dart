enum StudySetKind { flashcards, quiz }

enum StudyDifficulty { easy, medium, hard, mixed }

class Flashcard {
  const Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.pageNumber,
    this.sectionTitle,
  });

  factory Flashcard.fromJson(Map<String, dynamic> json) {
    final String front = (json['front'] as String? ?? '').trim();
    final String back = (json['back'] as String? ?? '').trim();
    if (front.isEmpty || back.isEmpty) {
      throw ArgumentError('Flashcard requires non-empty front and back.');
    }
    return Flashcard(
      id: json['id'] as String,
      front: front,
      back: back,
      pageNumber: json['pageNumber'] as int?,
      sectionTitle: json['sectionTitle'] as String?,
    );
  }

  final String id;
  final String front;
  final String back;
  final int? pageNumber;
  final String? sectionTitle;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'front': front,
    'back': back,
    'pageNumber': pageNumber,
    'sectionTitle': sectionTitle,
  };
}

class QuizQuestion {
  QuizQuestion({
    required this.id,
    required String prompt,
    required List<String> options,
    required this.correctIndex,
    required String explanation,
    this.pageNumber,
    required this.difficulty,
  }) : prompt = prompt.trim(),
       options = List<String>.unmodifiable(options),
       explanation = explanation.trim() {
    if (this.prompt.isEmpty) {
      throw ArgumentError('QuizQuestion prompt must not be empty.');
    }
    if (this.options.length != 4) {
      throw ArgumentError(
        'QuizQuestion requires exactly 4 options, got ${this.options.length}.',
      );
    }
    if (this.options.any((String option) => option.trim().isEmpty)) {
      throw ArgumentError('QuizQuestion options must not be empty.');
    }
    if (correctIndex < 0 || correctIndex > 3) {
      throw ArgumentError(
        'QuizQuestion correctIndex must be 0..3, got $correctIndex.',
      );
    }
    if (this.explanation.isEmpty) {
      throw ArgumentError('QuizQuestion explanation must not be empty.');
    }
  }

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    id: json['id'] as String,
    prompt: json['prompt'] as String? ?? '',
    options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic value) => value as String)
        .toList(growable: false),
    correctIndex: json['correctIndex'] as int? ?? -1,
    explanation: json['explanation'] as String? ?? '',
    pageNumber: json['pageNumber'] as int?,
    difficulty: StudyDifficulty.values.byName(
      json['difficulty'] as String? ?? StudyDifficulty.mixed.name,
    ),
  );

  final String id;
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
  final int? pageNumber;
  final StudyDifficulty difficulty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'prompt': prompt,
    'options': options,
    'correctIndex': correctIndex,
    'explanation': explanation,
    'pageNumber': pageNumber,
    'difficulty': difficulty.name,
  };
}

class StudyGenerationConfig {
  StudyGenerationConfig({
    required this.kind,
    required int itemCount,
    required this.difficulty,
    String? focus,
  }) : itemCount = itemCount.clamp(5, 40),
       focus = (focus == null || focus.trim().isEmpty) ? null : focus.trim();

  factory StudyGenerationConfig.fromJson(Map<String, dynamic> json) =>
      StudyGenerationConfig(
        kind: StudySetKind.values.byName(json['kind'] as String),
        itemCount: json['itemCount'] as int,
        difficulty: StudyDifficulty.values.byName(
          json['difficulty'] as String,
        ),
        focus: json['focus'] as String?,
      );

  final StudySetKind kind;
  final int itemCount;
  final StudyDifficulty difficulty;
  final String? focus;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.name,
    'itemCount': itemCount,
    'difficulty': difficulty.name,
    'focus': focus,
  };
}

class StudySet {
  const StudySet({
    required this.id,
    required this.documentId,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.modelLabel,
    required this.generatedOnDevice,
    required this.config,
    required this.isPartial,
    this.cards = const <Flashcard>[],
    this.questions = const <QuizQuestion>[],
  });

  factory StudySet.fromJson(Map<String, dynamic> json) => StudySet(
    id: json['id'] as String,
    documentId: json['documentId'] as String,
    kind: StudySetKind.values.byName(json['kind'] as String),
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    modelLabel: json['modelLabel'] as String?,
    generatedOnDevice: json['generatedOnDevice'] as bool,
    config: StudyGenerationConfig.fromJson(
      json['config'] as Map<String, dynamic>,
    ),
    isPartial: json['isPartial'] as bool,
    cards: (json['cards'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (dynamic value) => Flashcard.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    questions: (json['questions'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (dynamic value) =>
              QuizQuestion.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
  );

  final String id;
  final String documentId;
  final StudySetKind kind;
  final String title;
  final DateTime createdAt;
  final String? modelLabel;
  final bool generatedOnDevice;
  final StudyGenerationConfig config;
  final bool isPartial;
  final List<Flashcard> cards;
  final List<QuizQuestion> questions;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'documentId': documentId,
    'kind': kind.name,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'modelLabel': modelLabel,
    'generatedOnDevice': generatedOnDevice,
    'config': config.toJson(),
    'isPartial': isPartial,
    'cards': cards.map((Flashcard card) => card.toJson()).toList(),
    'questions': questions
        .map((QuizQuestion question) => question.toJson())
        .toList(),
  };
}

class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.setId,
    required this.startedAt,
    this.completedAt,
    required this.answers,
    required this.correctCount,
  });

  factory QuizAttempt.fromJson(Map<String, dynamic> json) => QuizAttempt(
    id: json['id'] as String,
    setId: json['setId'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
    completedAt: json['completedAt'] == null
        ? null
        : DateTime.parse(json['completedAt'] as String),
    answers: (json['answers'] as Map<String, dynamic>).map(
      (String key, dynamic value) => MapEntry<String, int>(key, value as int),
    ),
    correctCount: json['correctCount'] as int,
  );

  final String id;
  final String setId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Map<String, int> answers;
  final int correctCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'setId': setId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'answers': answers,
    'correctCount': correctCount,
  };
}
