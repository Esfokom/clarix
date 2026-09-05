import 'package:clarix/src/features/ai/ai.dart';

import '../domain/study_models.dart';

/// Gemma 4 E2B's on-device context window. There is no field for this on
/// [LocalModelProfile] (it only stores install/download identity), so it is
/// named here as the single place to update if the bundled model changes.
const int kLocalContextTokens = 32768;

class StudyTarget {
  const StudyTarget({
    required this.profileId,
    required this.contextWindowTokens,
    required this.label,
    required this.isLocal,
  });

  factory StudyTarget.remote(AiProviderProfile profile) => StudyTarget(
    profileId: profile.id,
    contextWindowTokens: profile.contextWindowTokens,
    label: profile.label,
    isLocal: false,
  );

  factory StudyTarget.local(LocalModelProfile profile) => StudyTarget(
    profileId: profile.id,
    contextWindowTokens: kLocalContextTokens,
    label: profile.label,
    isLocal: true,
  );

  final String profileId;
  final int contextWindowTokens;
  final String label;
  final bool isLocal;
}

class StudyBudget {
  const StudyBudget({
    required this.promptBudgetTokens,
    required this.batchCount,
    required this.itemQuotaPerBatch,
  });

  static const int _flashcardPerItemCost = 90;
  static const int _quizPerItemCost = 220;
  static const int _instructionOverheadTokens = 400;
  static const int _minReservedTokens = 512;

  factory StudyBudget.forTarget({
    required StudyTarget target,
    required StudyGenerationConfig config,
    required int totalSourceTokens,
  }) {
    final int perItemCost = config.kind == StudySetKind.flashcards
        ? _flashcardPerItemCost
        : _quizPerItemCost;
    final int halfWindow = target.contextWindowTokens ~/ 2;
    final int reserved = (config.itemCount * perItemCost).clamp(
      _minReservedTokens,
      halfWindow,
    );
    final int promptBudget =
        (target.contextWindowTokens - reserved - _instructionOverheadTokens)
            .clamp(1, target.contextWindowTokens);

    final int batchCount = totalSourceTokens <= 0
        ? 1
        : (totalSourceTokens / promptBudget).ceil().clamp(1, 1 << 20);

    final int baseQuota = config.itemCount ~/ batchCount;
    final int remainder = config.itemCount - baseQuota * batchCount;
    final List<int> quotas = List<int>.generate(
      batchCount,
      (int index) => baseQuota + (index < remainder ? 1 : 0),
    );

    return StudyBudget(
      promptBudgetTokens: promptBudget,
      batchCount: batchCount,
      itemQuotaPerBatch: quotas,
    );
  }

  final int promptBudgetTokens;
  final int batchCount;
  final List<int> itemQuotaPerBatch;
}
