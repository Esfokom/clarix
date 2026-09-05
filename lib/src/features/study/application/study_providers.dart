import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/study_store.dart';
import 'study_notifier.dart';
import 'study_service.dart';
import 'study_source_planner.dart';

final studyStoreProvider = FutureProvider<StudyStore>((Ref ref) async {
  final StudyStore store = StudyStore();
  await store.initialize();
  return store;
});

final studySourcePlannerProvider = Provider<StudySourcePlanner>(
  (Ref ref) => StudySourcePlanner(
    chunkStore: ref.watch(chunkStoreProvider),
    ragService: ref.watch(localRagServiceProvider),
  ),
);

final studyServiceProvider = FutureProvider<StudyService>((Ref ref) async {
  final StudyStore store = await ref.watch(studyStoreProvider.future);
  return StudyService(
    aiRuntimeService: ref.watch(aiRuntimeServiceProvider),
    sourcePlanner: ref.watch(studySourcePlannerProvider),
    store: store,
    aiPreferences: ref.watch(aiPreferencesStoreProvider),
    providerProfiles: ref.watch(providerProfileStoreProvider),
    localModels: ref.watch(localModelStoreProvider),
  );
});

final studyNotifierProvider =
    AsyncNotifierProvider<StudyNotifier, StudyFeatureState>(StudyNotifier.new);
