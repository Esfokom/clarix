import 'dart:async';
import 'dart:io';

import 'package:clarix/src/core/cancel_token.dart';
import 'package:clarix/src/features/ai/ai.dart';

import '../domain/study_models.dart';
import '../infrastructure/study_store.dart';
import 'study_budget.dart';
import 'study_generation_harness.dart';
import 'study_source_planner.dart';

class StudyFallbackOffer {
  const StudyFallbackOffer({
    required this.documentId,
    required this.config,
    required this.reason,
  });
  final String documentId;
  final StudyGenerationConfig config;
  final String reason;
}

class StudyNetworkFailure implements Exception {
  const StudyNetworkFailure({
    required this.documentId,
    required this.config,
    required this.reason,
  });
  final String documentId;
  final StudyGenerationConfig config;
  final String reason;

  StudyFallbackOffer toOffer() => StudyFallbackOffer(
    documentId: documentId,
    config: config,
    reason: reason,
  );
}

class StudyRunResult {
  const StudyRunResult({required this.studySet, required this.warnings});
  final StudySet studySet;
  final List<String> warnings;
}

class StudyService {
  StudyService({
    required this.aiRuntimeService,
    required this.sourcePlanner,
    required this.store,
    required this.aiPreferences,
    required this.providerProfiles,
    required this.localModels,
  });

  final AiRuntimeService aiRuntimeService;
  final StudySourcePlanner sourcePlanner;
  final StudyStore store;
  final AiPreferencesStore aiPreferences;
  final ProviderProfileStore providerProfiles;
  final LocalModelStore localModels;

  Future<StudyRunResult> generate({
    required String documentId,
    required StudyGenerationConfig config,
    void Function(StudyRunProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final AiWorkspaceState prefs = await aiPreferences.readState();
    final String? profileId = prefs.selectedProviderId;
    if (profileId == null) {
      throw StateError(
        'Select an AI provider in settings before generating a study set.',
      );
    }
    final StudyTarget target = await _resolveTarget(profileId);
    return generateWithTarget(
      documentId: documentId,
      config: config,
      target: target,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<StudyRunResult> generateWithTarget({
    required String documentId,
    required StudyGenerationConfig config,
    required StudyTarget target,
    void Function(StudyRunProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final StudyRunPlan plan = await sourcePlanner.plan(
      documentId: documentId,
      config: config,
      target: target,
    );
    if (plan.batches.isEmpty) {
      throw StateError('This document has not been indexed yet.');
    }
    return generateFromPlan(
      documentId: documentId,
      config: config,
      target: target,
      plan: plan,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Runs generation against an already-computed [plan]. Exposed separately
  /// from [generateWithTarget] so a local-target retry after a
  /// [StudyNetworkFailure] can re-plan once (context window differs) without
  /// re-deriving source selection twice.
  Future<StudyRunResult> generateFromPlan({
    required String documentId,
    required StudyGenerationConfig config,
    required StudyTarget target,
    required StudyRunPlan plan,
    void Function(StudyRunProgress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final StudyGenerationHarness harness = StudyGenerationHarness(
      aiRuntimeService: aiRuntimeService,
    );
    try {
      await for (final StudyRunProgress progress in harness.run(
        plan: plan,
        target: target,
        config: config,
        cancelToken: cancelToken,
      )) {
        onProgress?.call(progress);
      }
    } on SocketException catch (error) {
      throw StudyNetworkFailure(
        documentId: documentId,
        config: config,
        reason: error.message,
      );
    } on TimeoutException catch (error) {
      throw StudyNetworkFailure(
        documentId: documentId,
        config: config,
        reason: error.message ?? 'Request timed out.',
      );
    } on HttpException catch (error) {
      throw StudyNetworkFailure(
        documentId: documentId,
        config: config,
        reason: error.message,
      );
    }

    final int totalAccepted =
        harness.flashcards.length + harness.questions.length;
    if (totalAccepted == 0) {
      throw StateError(
        'Could not generate any items. ${harness.warnings.join(' ')}',
      );
    }
    final bool isPartial =
        (cancelToken?.isCancelled ?? false) || totalAccepted < config.itemCount;
    final StudySet studySet = StudySet(
      id: 'study_${DateTime.now().toUtc().microsecondsSinceEpoch}',
      documentId: documentId,
      kind: config.kind,
      title: _titleFor(config),
      createdAt: DateTime.now().toUtc(),
      modelLabel: target.label,
      generatedOnDevice: target.isLocal,
      config: config,
      isPartial: isPartial,
      cards: harness.flashcards,
      questions: harness.questions,
    );
    await store.saveStudySet(studySet);
    return StudyRunResult(studySet: studySet, warnings: harness.warnings);
  }

  Future<StudyTarget> _resolveTarget(String profileId) async {
    final List<LocalModelProfile> locals = await localModels.readAll();
    final LocalModelProfile? local = locals
        .where((LocalModelProfile item) => item.id == profileId)
        .firstOrNull;
    if (local != null) return StudyTarget.local(local);

    final List<AiProviderProfile> remotes = await providerProfiles
        .readProfiles();
    final AiProviderProfile? remote = remotes
        .where((AiProviderProfile item) => item.id == profileId)
        .firstOrNull;
    if (remote == null) {
      throw StateError('Selected provider is no longer configured.');
    }
    return StudyTarget.remote(remote);
  }

  String _titleFor(StudyGenerationConfig config) {
    final String kindLabel = config.kind == StudySetKind.flashcards
        ? 'Flashcards'
        : 'Quiz';
    return config.focus == null
        ? '$kindLabel — ${config.itemCount} items'
        : '$kindLabel — ${config.focus}';
  }
}
