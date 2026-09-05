enum TtsEngineKind { kitten, kokoro }

/// Describes a downloadable sherpa-onnx TTS voice pack.
class TtsModelSpec {
  const TtsModelSpec({
    required this.id,
    required this.engine,
    required this.label,
    required this.description,
    required this.downloadUrl,
    required this.approxArchiveSizeBytes,
    required this.modelFileName,
    required this.voicesFileName,
    required this.tokensFileName,
    required this.dataDirName,
  });

  final String id;
  final TtsEngineKind engine;
  final String label;
  final String description;
  final String downloadUrl;
  final int approxArchiveSizeBytes;
  final String modelFileName;
  final String voicesFileName;
  final String tokensFileName;
  final String dataDirName;
}

enum TtsInstallStatus { notInstalled, downloading, extracting, installed, failed }

class TtsModelInstallState {
  const TtsModelInstallState({
    this.status = TtsInstallStatus.notInstalled,
    this.progress = 0,
    this.errorMessage,
  });

  final TtsInstallStatus status;

  /// 0..1 for [TtsInstallStatus.downloading]; unspecified otherwise.
  final double progress;
  final String? errorMessage;

  TtsModelInstallState copyWith({
    TtsInstallStatus? status,
    double? progress,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsModelInstallState(
    status: status ?? this.status,
    progress: progress ?? this.progress,
    errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
  );
}

enum TtsPlaybackStatus { idle, preparing, speaking, paused }

class TtsPlaybackState {
  const TtsPlaybackState({
    this.status = TtsPlaybackStatus.idle,
    this.documentId,
    this.segmentIndex = 0,
    this.segmentTotal = 0,
    this.currentPage,
    this.errorMessage,
  });

  final TtsPlaybackStatus status;
  final String? documentId;
  final int segmentIndex;
  final int segmentTotal;
  final int? currentPage;
  final String? errorMessage;

  TtsPlaybackState copyWith({
    TtsPlaybackStatus? status,
    String? documentId,
    bool clearDocumentId = false,
    int? segmentIndex,
    int? segmentTotal,
    int? currentPage,
    bool clearCurrentPage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsPlaybackState(
    status: status ?? this.status,
    documentId: clearDocumentId ? null : (documentId ?? this.documentId),
    segmentIndex: segmentIndex ?? this.segmentIndex,
    segmentTotal: segmentTotal ?? this.segmentTotal,
    currentPage: clearCurrentPage ? null : (currentPage ?? this.currentPage),
    errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
  );
}
