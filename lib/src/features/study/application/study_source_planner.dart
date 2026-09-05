import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/ai/ai.dart';

import '../domain/study_models.dart';
import 'study_budget.dart';

class StudyPageRange {
  const StudyPageRange({required this.start, required this.end});
  final int start;
  final int end;
}

class StudyBatch {
  const StudyBatch({
    required this.pageRange,
    required this.chunks,
    required this.itemQuota,
  });

  final StudyPageRange pageRange;
  final List<PdfChunkRecord> chunks;
  final int itemQuota;
}

class StudyRunPlan {
  const StudyRunPlan({
    required this.batches,
    required this.totalItems,
    required this.estimatedPromptTokens,
  });

  final List<StudyBatch> batches;
  final int totalItems;
  final int estimatedPromptTokens;
}

class StudySourcePlanner {
  StudySourcePlanner({required this.chunkStore, required this.ragService});

  final DocumentChunkStore chunkStore;
  final LocalRagService ragService;

  int retrieveLimitFor({required int itemCount}) => itemCount * 4;

  Future<StudyRunPlan> plan({
    required String documentId,
    required StudyGenerationConfig config,
    required StudyTarget target,
  }) async {
    final List<PdfChunkRecord> source = config.focus == null
        ? await chunkStore.readChunks(documentId)
        : await ragService.retrieve(
            documentId,
            config.focus!,
            limit: retrieveLimitFor(itemCount: config.itemCount),
          );
    return planFromChunks(chunks: source, config: config, target: target);
  }

  Future<StudyRunPlan> planFromChunks({
    required List<PdfChunkRecord> chunks,
    required StudyGenerationConfig config,
    required StudyTarget target,
  }) async {
    if (chunks.isEmpty) {
      return const StudyRunPlan(
        batches: <StudyBatch>[],
        totalItems: 0,
        estimatedPromptTokens: 0,
      );
    }

    final List<PdfChunkRecord> sorted = List<PdfChunkRecord>.of(chunks)
      ..sort((PdfChunkRecord a, PdfChunkRecord b) {
        final int byPage = a.pageNumber.compareTo(b.pageNumber);
        return byPage != 0 ? byPage : a.chunkOrder.compareTo(b.chunkOrder);
      });

    final int totalSourceTokens = sorted.fold(
      0,
      (int sum, PdfChunkRecord chunk) => sum + estimateTokens(chunk.text),
    );
    final StudyBudget budget = StudyBudget.forTarget(
      target: target,
      config: config,
      totalSourceTokens: totalSourceTokens,
    );

    final List<List<PdfChunkRecord>> groups = <List<PdfChunkRecord>>[];
    List<PdfChunkRecord> current = <PdfChunkRecord>[];
    int currentTokens = 0;
    for (final PdfChunkRecord chunk in sorted) {
      final int chunkTokens = estimateTokens(chunk.text);
      if (current.isNotEmpty &&
          currentTokens + chunkTokens > budget.promptBudgetTokens) {
        groups.add(current);
        current = <PdfChunkRecord>[];
        currentTokens = 0;
      }
      current.add(chunk);
      currentTokens += chunkTokens;
    }
    if (current.isNotEmpty) groups.add(current);

    List<List<PdfChunkRecord>> selected = groups;
    if (groups.length > config.itemCount) {
      final double stride = groups.length / config.itemCount;
      final Set<int> indexSet = <int>{0, groups.length - 1};
      for (int i = 0; i < config.itemCount; i++) {
        indexSet.add((i * stride).floor().clamp(0, groups.length - 1));
      }
      final List<int> uniqueSorted = indexSet.toList()..sort();
      final List<int> trimmed = uniqueSorted.length > config.itemCount
          ? uniqueSorted.sublist(0, config.itemCount)
          : uniqueSorted;
      selected = <List<PdfChunkRecord>>[
        for (final int index in trimmed) groups[index],
      ];
    }

    final int batchCount = selected.length;
    final int baseQuota = config.itemCount ~/ batchCount;
    final int remainder = config.itemCount - baseQuota * batchCount;
    final List<StudyBatch> batches = <StudyBatch>[
      for (int i = 0; i < batchCount; i++)
        StudyBatch(
          pageRange: StudyPageRange(
            start: selected[i].first.pageNumber,
            end: selected[i].last.pageNumber,
          ),
          chunks: selected[i],
          itemQuota: baseQuota + (i < remainder ? 1 : 0),
        ),
    ];

    return StudyRunPlan(
      batches: batches,
      totalItems: config.itemCount,
      estimatedPromptTokens: totalSourceTokens,
    );
  }
}
