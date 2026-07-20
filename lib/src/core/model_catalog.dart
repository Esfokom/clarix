
import 'local_gemma_model_store.dart';
import 'models.dart';

class ClarixModelCatalog {
  const ClarixModelCatalog({
    this.localModelStore = const LocalGemmaModelStore(),
  });

  final LocalGemmaModelStore localModelStore;

  List<ModelCatalogItem> buildCatalog({
    required Map<String, DownloadTaskState> downloads,
  }) {
    final List<ModelCatalogItem> items = <ModelCatalogItem>[
      const ModelCatalogItem(
        id: 'gemma-4-e2b-it',
        label: 'Gemma 4 E2B IT',
        family: 'Gemma 4',
        type: ModelCatalogType.inference,
        sizeBytes: 2583 * 1024 * 1024,
        platforms: <String>['Windows', 'macOS', 'Linux', 'Android', 'iOS'],
        installState: ModelInstallState.notInstalled,
        modelUrl:
            'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
        filename: 'gemma-4-E2B-it.litertlm',
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
        description:
            'Recommended default. Better install size and memory profile for multi-document desktop work.',
      ),
      const ModelCatalogItem(
        id: 'gemma-4-e4b-it',
        label: 'Gemma 4 E4B IT',
        family: 'Gemma 4',
        type: ModelCatalogType.inference,
        sizeBytes: 4300 * 1024 * 1024,
        platforms: <String>['Windows', 'macOS', 'Linux', 'Android', 'iOS'],
        installState: ModelInstallState.notInstalled,
        modelUrl:
            'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
        filename: 'gemma-4-E4B-it.litertlm',
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
        description:
            'Higher-quality variant with a larger disk and memory footprint.',
      ),
      const ModelCatalogItem(
        id: 'embedding-gemma-1024',
        label: 'EmbeddingGemma 1024',
        family: 'EmbeddingGemma',
        type: ModelCatalogType.embedding,
        sizeBytes: 183 * 1024 * 1024,
        platforms: <String>['Windows', 'macOS', 'Linux', 'Android', 'iOS'],
        installState: ModelInstallState.notInstalled,
        modelUrl:
            'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq1024_mixed-precision.tflite',
        filename: 'embeddinggemma-300M_seq1024_mixed-precision.tflite',
        tokenizerUrl:
            'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
        description:
            'Good default for long-form PDF retrieval with page-aware chunking.',
      ),
    ];

    return items
        .map((ModelCatalogItem item) {
          final DownloadTaskState task =
              downloads[item.id] ?? DownloadTaskState.initial(item.id);
          final String? localPath = localModelStore.installedPathSync(item);
          final String? installedPath = task.installedPath ?? localPath;
          final ModelInstallState installState = switch (task.status) {
            DownloadTaskStatus.completed => ModelInstallState.installed,
            DownloadTaskStatus.running ||
            DownloadTaskStatus.validating => ModelInstallState.downloading,
            DownloadTaskStatus.failed => ModelInstallState.failed,
            _ => installedPath == null
                ? item.installState
                : ModelInstallState.installed,
          };
          return item.copyWith(
            installState: installState,
            installedPath: installedPath,
          );
        })
        .toList(growable: false);
  }
}
