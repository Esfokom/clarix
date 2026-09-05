import 'package:clarix/src/core/cancel_token.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/study_models.dart';
import 'study_budget.dart';
import 'study_generation_harness.dart';
import 'study_providers.dart';
import 'study_service.dart';

class StudyRunState {
  const StudyRunState({
    required this.kind,
    required this.batchIndex,
    required this.batchCount,
    required this.itemsAccepted,
    required this.itemsRequested,
    required this.warnings,
    required this.cancelToken,
  });

  final StudySetKind kind;
  final int batchIndex;
  final int batchCount;
  final int itemsAccepted;
  final int itemsRequested;
  final List<String> warnings;
  final CancelToken cancelToken;

  StudyRunState copyWith({
    int? batchIndex,
    int? batchCount,
    int? itemsAccepted,
    List<String>? warnings,
  }) => StudyRunState(
    kind: kind,
    batchIndex: batchIndex ?? this.batchIndex,
    batchCount: batchCount ?? this.batchCount,
    itemsAccepted: itemsAccepted ?? this.itemsAccepted,
    itemsRequested: itemsRequested,
    warnings: warnings ?? this.warnings,
    cancelToken: cancelToken,
  );
}

class StudyFeatureState {
  const StudyFeatureState({
    required this.setsByDocument,
    this.activeRun,
    this.pendingOffer,
    this.errorMessage,
  });

  factory StudyFeatureState.initial() =>
      const StudyFeatureState(setsByDocument: <String, List<StudySet>>{});

  final Map<String, List<StudySet>> setsByDocument;
  final StudyRunState? activeRun;
  final StudyFallbackOffer? pendingOffer;
  final String? errorMessage;

  StudyFeatureState copyWith({
    Map<String, List<StudySet>>? setsByDocument,
    StudyRunState? activeRun,
    bool clearActiveRun = false,
    StudyFallbackOffer? pendingOffer,
    bool clearPendingOffer = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => StudyFeatureState(
    setsByDocument: setsByDocument ?? this.setsByDocument,
    activeRun: clearActiveRun ? null : (activeRun ?? this.activeRun),
    pendingOffer: clearPendingOffer
        ? null
        : (pendingOffer ?? this.pendingOffer),
    errorMessage: clearErrorMessage
        ? null
        : (errorMessage ?? this.errorMessage),
  );
}

class StudyNotifier extends AsyncNotifier<StudyFeatureState> {
  @override
  Future<StudyFeatureState> build() async => StudyFeatureState.initial();

  StudyFeatureState get _current => state.value ?? StudyFeatureState.initial();

  void _commit(StudyFeatureState value) {
    state = AsyncData<StudyFeatureState>(value);
  }

  Future<void> loadSets(String documentId) async {
    final StudyService service = await ref.read(studyServiceProvider.future);
    final List<StudySet> sets = await service.store.listSets(documentId);
    final Map<String, List<StudySet>> next = Map<String, List<StudySet>>.of(
      _current.setsByDocument,
    )..[documentId] = sets;
    _commit(_current.copyWith(setsByDocument: next));
  }

  Future<void> generate({
    required String documentId,
    required StudyGenerationConfig config,
  }) async {
    if (_current.activeRun != null) return;
    final CancelToken cancelToken = CancelToken();
    _commit(
      _current.copyWith(
        activeRun: StudyRunState(
          kind: config.kind,
          batchIndex: 0,
          batchCount: 0,
          itemsAccepted: 0,
          itemsRequested: config.itemCount,
          warnings: const <String>[],
          cancelToken: cancelToken,
        ),
        clearPendingOffer: true,
        clearErrorMessage: true,
      ),
    );
    final StudyService service = await ref.read(studyServiceProvider.future);
    try {
      final StudyRunResult result = await service.generate(
        documentId: documentId,
        config: config,
        cancelToken: cancelToken,
        onProgress: (StudyRunProgress progress) => _applyProgress(progress),
      );
      _appendSet(documentId, result.studySet);
      _commit(_current.copyWith(clearActiveRun: true));
    } on StudyNetworkFailure catch (failure) {
      _commit(
        _current.copyWith(
          clearActiveRun: true,
          pendingOffer: failure.toOffer(),
        ),
      );
    } on StateError catch (error) {
      _commit(
        _current.copyWith(clearActiveRun: true, errorMessage: error.message),
      );
    }
  }

  void cancelRun() {
    _current.activeRun?.cancelToken.cancel();
  }

  Future<void> acceptFallback() async {
    final StudyFallbackOffer? offer = _current.pendingOffer;
    if (offer == null) return;
    final CancelToken cancelToken = CancelToken();
    _commit(
      _current.copyWith(
        activeRun: StudyRunState(
          kind: offer.config.kind,
          batchIndex: 0,
          batchCount: 0,
          itemsAccepted: 0,
          itemsRequested: offer.config.itemCount,
          warnings: const <String>[],
          cancelToken: cancelToken,
        ),
        clearPendingOffer: true,
      ),
    );
    final StudyService service = await ref.read(studyServiceProvider.future);
    try {
      final StudyRunResult result = await service.generateWithTarget(
        documentId: offer.documentId,
        config: offer.config,
        target: StudyTarget.local(LocalModelProfile.gemma4E2b()),
        cancelToken: cancelToken,
        onProgress: (StudyRunProgress progress) => _applyProgress(progress),
      );
      _appendSet(offer.documentId, result.studySet);
      _commit(_current.copyWith(clearActiveRun: true));
    } on StateError catch (error) {
      _commit(
        _current.copyWith(clearActiveRun: true, errorMessage: error.message),
      );
    }
  }

  void declineFallback() {
    _commit(_current.copyWith(clearPendingOffer: true));
  }

  Future<void> deleteSet(String documentId, String setId) async {
    final StudyService service = await ref.read(studyServiceProvider.future);
    await service.store.deleteSet(setId);
    await loadSets(documentId);
  }

  void _applyProgress(StudyRunProgress progress) {
    final StudyRunState? run = _current.activeRun;
    if (run == null) return;
    switch (progress) {
      case StudyBatchStarted(:final index, :final total):
        _commit(
          _current.copyWith(
            activeRun: run.copyWith(batchIndex: index, batchCount: total),
          ),
        );
      case StudyBatchCompleted(:final acceptedItems, :final warnings):
        _commit(
          _current.copyWith(
            activeRun: run.copyWith(
              itemsAccepted: run.itemsAccepted + acceptedItems,
              warnings: <String>[...run.warnings, ...warnings],
            ),
          ),
        );
    }
  }

  void _appendSet(String documentId, StudySet set) {
    final List<StudySet> existing =
        _current.setsByDocument[documentId] ?? const <StudySet>[];
    final Map<String, List<StudySet>> next = Map<String, List<StudySet>>.of(
      _current.setsByDocument,
    )..[documentId] = <StudySet>[set, ...existing];
    _commit(_current.copyWith(setsByDocument: next));
  }
}
