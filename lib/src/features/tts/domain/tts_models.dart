enum TtsEngineKind { kittenSherpa, piperSherpa, system }

/// Describes a downloadable sherpa-onnx TTS voice pack. Not used for
/// [TtsEngineKind.system], which has no on-disk model.
class TtsModelSpec {
  const TtsModelSpec({
    required this.id,
    required this.engine,
    required this.label,
    required this.description,
    required this.downloadUrl,
    required this.approxArchiveSizeBytes,
    required this.modelFileName,
    this.voicesFileName,
    required this.tokensFileName,
    required this.dataDirName,
    required this.voiceCount,
  });

  final String id;
  final TtsEngineKind engine;
  final String label;
  final String description;
  final String downloadUrl;
  final int approxArchiveSizeBytes;
  final String modelFileName;

  /// Null for single-speaker packages (e.g. Piper), which have no separate
  /// speaker-embedding file. Set for Kitten, which packs multiple voices into
  /// one `voices.bin`.
  final String? voicesFileName;
  final String tokensFileName;
  final String dataDirName;
  final int voiceCount;
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

/// A single unit of narration: one sentence (or sentence-like fragment)
/// extracted directly from a document page, with enough identity for the
/// reader to map it back to an on-page highlight.
class ReadAloudSegment {
  const ReadAloudSegment({
    required this.id,
    required this.text,
    required this.pageNumber,
  });

  final String id;
  final String text;
  final int pageNumber;
}

enum TtsPlaybackStatus { idle, preparing, speaking, paused }

class TtsPlaybackState {
  const TtsPlaybackState({
    this.status = TtsPlaybackStatus.idle,
    this.documentId,
    this.segmentIndex = 0,
    this.segmentTotal = 0,
    this.currentPage,
    this.currentSegmentId,
    this.errorMessage,
  });

  final TtsPlaybackStatus status;
  final String? documentId;
  final int segmentIndex;
  final int segmentTotal;
  final int? currentPage;
  final String? currentSegmentId;
  final String? errorMessage;

  TtsPlaybackState copyWith({
    TtsPlaybackStatus? status,
    String? documentId,
    bool clearDocumentId = false,
    int? segmentIndex,
    int? segmentTotal,
    int? currentPage,
    bool clearCurrentPage = false,
    String? currentSegmentId,
    bool clearCurrentSegmentId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) => TtsPlaybackState(
    status: status ?? this.status,
    documentId: clearDocumentId ? null : (documentId ?? this.documentId),
    segmentIndex: segmentIndex ?? this.segmentIndex,
    segmentTotal: segmentTotal ?? this.segmentTotal,
    currentPage: clearCurrentPage ? null : (currentPage ?? this.currentPage),
    currentSegmentId: clearCurrentSegmentId
        ? null
        : (currentSegmentId ?? this.currentSegmentId),
    errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
  );
}
