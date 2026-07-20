import 'dart:convert';

import 'package:flutter/material.dart';

enum SidebarPane { thumbnails, outline }

enum DocumentIndexStatus {
  idle,
  queued,
  indexing,
  indexed,
  unavailable,
  failed,
}

enum AiRuntimePhase {
  idle,
  restoringInference,
  restoringEmbedding,
  loadingInference,
  preparingGrounding,
  indexing,
  validatingProvider,
  retrieving,
  callingProvider,
  executingTool,
  generating,
  cancelled,
  failed,
}

enum DownloadTaskStatus { idle, running, paused, validating, failed, completed }

enum ModelCatalogType { inference, embedding }

enum ModelType { gemma4 }

enum ModelFileType { task, litertlm }

enum ModelInstallState { notInstalled, downloading, installed, failed }

class WorkspaceSession {
  const WorkspaceSession({
    required this.restorePreviousSession,
    required this.tabs,
    required this.activeTabId,
    required this.lastOpenedAt,
    required this.recentFiles,
    required this.sidebarPane,
  });

  factory WorkspaceSession.initial() => WorkspaceSession(
    restorePreviousSession: true,
    tabs: const <DocumentTabState>[],
    activeTabId: null,
    lastOpenedAt: DateTime.now().toUtc(),
    recentFiles: const <String>[],
    sidebarPane: SidebarPane.thumbnails,
  );

  factory WorkspaceSession.fromJson(Map<String, dynamic> json) {
    return WorkspaceSession(
      restorePreviousSession: json['restorePreviousSession'] as bool? ?? true,
      tabs: (json['tabs'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) =>
                DocumentTabState.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      activeTabId: json['activeTabId'] as String?,
      lastOpenedAt:
          DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      recentFiles: (json['recentFiles'] as List<dynamic>? ?? const <dynamic>[])
          .cast<String>()
          .toList(growable: false),
      sidebarPane: SidebarPane.values.byName(
        json['sidebarPane'] as String? ?? SidebarPane.thumbnails.name,
      ),
    );
  }

  final bool restorePreviousSession;
  final List<DocumentTabState> tabs;
  final String? activeTabId;
  final DateTime lastOpenedAt;
  final List<String> recentFiles;
  final SidebarPane sidebarPane;

  WorkspaceSession copyWith({
    bool? restorePreviousSession,
    List<DocumentTabState>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
    DateTime? lastOpenedAt,
    List<String>? recentFiles,
    SidebarPane? sidebarPane,
  }) {
    return WorkspaceSession(
      restorePreviousSession:
          restorePreviousSession ?? this.restorePreviousSession,
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : activeTabId ?? this.activeTabId,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      recentFiles: recentFiles ?? this.recentFiles,
      sidebarPane: sidebarPane ?? this.sidebarPane,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'restorePreviousSession': restorePreviousSession,
    'tabs': tabs.map((DocumentTabState tab) => tab.toJson()).toList(),
    'activeTabId': activeTabId,
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'recentFiles': recentFiles,
    'sidebarPane': sidebarPane.name,
  };
}

class DocumentTabState {
  const DocumentTabState({
    required this.id,
    required this.documentId,
    required this.filePath,
    required this.title,
    required this.currentPage,
    required this.zoomScale,
    required this.scrollOffsetX,
    required this.scrollOffsetY,
    required this.searchQuery,
    required this.selectedSearchResult,
    required this.outlineExpanded,
    required this.indexStatus,
    required this.missingFileMessage,
    required this.lastOpenedAt,
    required this.pageCountHint,
  });

  factory DocumentTabState.create({
    required String id,
    required String documentId,
    required String filePath,
    required String title,
  }) {
    return DocumentTabState(
      id: id,
      documentId: documentId,
      filePath: filePath,
      title: title,
      currentPage: 1,
      zoomScale: 1,
      scrollOffsetX: 0,
      scrollOffsetY: 0,
      searchQuery: '',
      selectedSearchResult: 0,
      outlineExpanded: true,
      indexStatus: DocumentIndexStatus.queued,
      missingFileMessage: null,
      lastOpenedAt: DateTime.now().toUtc(),
      pageCountHint: null,
    );
  }

  factory DocumentTabState.fromJson(Map<String, dynamic> json) {
    return DocumentTabState(
      id: json['id'] as String,
      documentId: json['documentId'] as String,
      filePath: json['filePath'] as String,
      title: json['title'] as String,
      currentPage: json['currentPage'] as int? ?? 1,
      zoomScale: (json['zoomScale'] as num?)?.toDouble() ?? 1,
      scrollOffsetX: (json['scrollOffsetX'] as num?)?.toDouble() ?? 0,
      scrollOffsetY: (json['scrollOffsetY'] as num?)?.toDouble() ?? 0,
      searchQuery: json['searchQuery'] as String? ?? '',
      selectedSearchResult: json['selectedSearchResult'] as int? ?? 0,
      outlineExpanded: json['outlineExpanded'] as bool? ?? true,
      indexStatus: DocumentIndexStatus.values.byName(
        json['indexStatus'] as String? ?? DocumentIndexStatus.idle.name,
      ),
      missingFileMessage: json['missingFileMessage'] as String?,
      lastOpenedAt:
          DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      pageCountHint: json['pageCountHint'] as int?,
    );
  }

  final String id;
  final String documentId;
  final String filePath;
  final String title;
  final int currentPage;
  final double zoomScale;
  final double scrollOffsetX;
  final double scrollOffsetY;
  final String searchQuery;
  final int selectedSearchResult;
  final bool outlineExpanded;
  final DocumentIndexStatus indexStatus;
  final String? missingFileMessage;
  final DateTime lastOpenedAt;
  final int? pageCountHint;

  bool get isMissingFile => missingFileMessage != null;

  DocumentTabState copyWith({
    String? documentId,
    String? filePath,
    String? title,
    int? currentPage,
    double? zoomScale,
    double? scrollOffsetX,
    double? scrollOffsetY,
    String? searchQuery,
    int? selectedSearchResult,
    bool? outlineExpanded,
    DocumentIndexStatus? indexStatus,
    String? missingFileMessage,
    bool clearMissingFileMessage = false,
    DateTime? lastOpenedAt,
    int? pageCountHint,
  }) {
    return DocumentTabState(
      id: id,
      documentId: documentId ?? this.documentId,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      currentPage: currentPage ?? this.currentPage,
      zoomScale: zoomScale ?? this.zoomScale,
      scrollOffsetX: scrollOffsetX ?? this.scrollOffsetX,
      scrollOffsetY: scrollOffsetY ?? this.scrollOffsetY,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedSearchResult: selectedSearchResult ?? this.selectedSearchResult,
      outlineExpanded: outlineExpanded ?? this.outlineExpanded,
      indexStatus: indexStatus ?? this.indexStatus,
      missingFileMessage: clearMissingFileMessage
          ? null
          : missingFileMessage ?? this.missingFileMessage,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      pageCountHint: pageCountHint ?? this.pageCountHint,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'documentId': documentId,
    'filePath': filePath,
    'title': title,
    'currentPage': currentPage,
    'zoomScale': zoomScale,
    'scrollOffsetX': scrollOffsetX,
    'scrollOffsetY': scrollOffsetY,
    'searchQuery': searchQuery,
    'selectedSearchResult': selectedSearchResult,
    'outlineExpanded': outlineExpanded,
    'indexStatus': indexStatus.name,
    'missingFileMessage': missingFileMessage,
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'pageCountHint': pageCountHint,
  };
}

class ModelCatalogItem {
  const ModelCatalogItem({
    required this.id,
    required this.label,
    required this.family,
    required this.type,
    required this.sizeBytes,
    required this.platforms,
    required this.installState,
    required this.modelUrl,
    required this.filename,
    this.tokenizerUrl,
    this.modelType,
    this.fileType = ModelFileType.task,
    this.description,
    this.installedPath,
  });

  final String id;
  final String label;
  final String family;
  final ModelCatalogType type;
  final int sizeBytes;
  final List<String> platforms;
  final ModelInstallState installState;
  final String modelUrl;
  final String filename;
  final String? tokenizerUrl;
  final ModelType? modelType;
  final ModelFileType fileType;
  final String? description;
  final String? installedPath;

  ModelCatalogItem copyWith({
    ModelInstallState? installState,
    String? installedPath,
    bool clearInstalledPath = false,
  }) {
    return ModelCatalogItem(
      id: id,
      label: label,
      family: family,
      type: type,
      sizeBytes: sizeBytes,
      platforms: platforms,
      installState: installState ?? this.installState,
      modelUrl: modelUrl,
      filename: filename,
      tokenizerUrl: tokenizerUrl,
      modelType: modelType,
      fileType: fileType,
      description: description,
      installedPath: clearInstalledPath
          ? null
          : installedPath ?? this.installedPath,
    );
  }
}

class DownloadTaskState {
  const DownloadTaskState({
    required this.taskId,
    required this.modelId,
    required this.status,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.lastUpdatedAt,
    required this.errorMessage,
    required this.installedPath,
  });

  factory DownloadTaskState.initial(String modelId) {
    return DownloadTaskState(
      taskId: modelId,
      modelId: modelId,
      status: DownloadTaskStatus.idle,
      progress: 0,
      downloadedBytes: 0,
      totalBytes: null,
      lastUpdatedAt: DateTime.now().toUtc(),
      errorMessage: null,
      installedPath: null,
    );
  }

  factory DownloadTaskState.fromJson(Map<String, dynamic> json) {
    return DownloadTaskState(
      taskId: json['taskId'] as String,
      modelId: json['modelId'] as String,
      status: DownloadTaskStatus.values.byName(
        json['status'] as String? ?? DownloadTaskStatus.idle.name,
      ),
      progress: json['progress'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int?,
      lastUpdatedAt:
          DateTime.tryParse(json['lastUpdatedAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      errorMessage: json['errorMessage'] as String?,
      installedPath: json['installedPath'] as String?,
    );
  }

  final String taskId;
  final String modelId;
  final DownloadTaskStatus status;
  final int progress;
  final int downloadedBytes;
  final int? totalBytes;
  final DateTime lastUpdatedAt;
  final String? errorMessage;
  final String? installedPath;

  DownloadTaskState copyWith({
    DownloadTaskStatus? status,
    int? progress,
    int? downloadedBytes,
    int? totalBytes,
    DateTime? lastUpdatedAt,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? installedPath,
    bool clearInstalledPath = false,
  }) {
    return DownloadTaskState(
      taskId: taskId,
      modelId: modelId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      installedPath: clearInstalledPath
          ? null
          : installedPath ?? this.installedPath,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'taskId': taskId,
    'modelId': modelId,
    'status': status.name,
    'progress': progress,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
    'errorMessage': errorMessage,
    'installedPath': installedPath,
  };
}

class AiWorkspaceState {
  const AiWorkspaceState({
    required this.providerReady,
    required this.selectedProviderId,
    required this.chatBusy,
    required this.activityPhase,
    required this.statusMessage,
    required this.messages,
    required this.useCurrentDocumentScope,
    required this.lastRetrievalSnippets,
  });

  final bool providerReady;
  final String? selectedProviderId;
  final bool chatBusy;
  final AiRuntimePhase activityPhase;
  final String statusMessage;
  final List<ComposerMessage> messages;
  final bool useCurrentDocumentScope;
  final List<CitationSnippet> lastRetrievalSnippets;

  factory AiWorkspaceState.initial() => const AiWorkspaceState(
    providerReady: false,
    selectedProviderId: null,
    chatBusy: false,
    activityPhase: AiRuntimePhase.idle,
    statusMessage: 'Add a provider to start a remote AI chat.',
    messages: <ComposerMessage>[],
    useCurrentDocumentScope: true,
    lastRetrievalSnippets: <CitationSnippet>[],
  );

  AiWorkspaceState copyWith({
    bool? providerReady,
    String? selectedProviderId,
    bool clearSelectedProviderId = false,
    bool? chatBusy,
    AiRuntimePhase? activityPhase,
    String? statusMessage,
    List<ComposerMessage>? messages,
    bool? useCurrentDocumentScope,
    List<CitationSnippet>? lastRetrievalSnippets,
  }) {
    return AiWorkspaceState(
      providerReady: providerReady ?? this.providerReady,
      selectedProviderId: clearSelectedProviderId
          ? null
          : selectedProviderId ?? this.selectedProviderId,
      chatBusy: chatBusy ?? this.chatBusy,
      activityPhase: activityPhase ?? this.activityPhase,
      statusMessage: statusMessage ?? this.statusMessage,
      messages: messages ?? this.messages,
      useCurrentDocumentScope:
          useCurrentDocumentScope ?? this.useCurrentDocumentScope,
      lastRetrievalSnippets:
          lastRetrievalSnippets ?? this.lastRetrievalSnippets,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'providerReady': providerReady,
    'selectedProviderId': selectedProviderId,
    'activityPhase': activityPhase.name,
    'statusMessage': statusMessage,
    'useCurrentDocumentScope': useCurrentDocumentScope,
  };

  factory AiWorkspaceState.fromJson(Map<String, dynamic> json) {
    return AiWorkspaceState.initial().copyWith(
      providerReady: json['providerReady'] as bool? ?? false,
      selectedProviderId: json['selectedProviderId'] as String?,
      activityPhase: AiRuntimePhase.idle,
      statusMessage: json['selectedProviderId'] == null
          ? 'Add a provider to start a remote AI chat.'
          : json['statusMessage'] as String?,
      useCurrentDocumentScope: json['useCurrentDocumentScope'] as bool? ?? true,
    );
  }
}

class ComposerMessage {
  const ComposerMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    required this.citations,
  });

  final String id;
  final String role;
  final String text;
  final DateTime createdAt;
  final List<CitationSnippet> citations;

  bool get isUser => role == 'user';

  ComposerMessage copyWith({String? text, List<CitationSnippet>? citations}) {
    return ComposerMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      citations: citations ?? this.citations,
    );
  }
}

class CitationSnippet {
  const CitationSnippet({
    required this.documentId,
    required this.label,
    required this.pageNumber,
    required this.snippet,
  });

  final String documentId;
  final String label;
  final int pageNumber;
  final String snippet;

  factory CitationSnippet.fromMetadata({
    required String content,
    required Object? metadata,
  }) {
    Map<String, dynamic> decoded = const <String, dynamic>{};
    if (metadata is String && metadata.isNotEmpty) {
      final dynamic parsed = jsonDecode(metadata);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } else if (metadata is Map<String, dynamic>) {
      decoded = metadata;
    }

    return CitationSnippet(
      documentId: decoded['documentId'] as String? ?? 'unknown-document',
      label: decoded['title'] as String? ?? 'PDF context',
      pageNumber: decoded['pageNumber'] as int? ?? 1,
      snippet: content,
    );
  }
}

class PdfChunkRecord {
  const PdfChunkRecord({
    required this.id,
    required this.documentId,
    required this.title,
    required this.pageNumber,
    required this.chunkOrder,
    required this.text,
    this.sectionTitle,
  });

  final String id;
  final String documentId;
  final String title;
  final int pageNumber;
  final int chunkOrder;
  final String text;
  final String? sectionTitle;

  String get metadataJson {
    return jsonEncode(<String, dynamic>{
      'documentId': documentId,
      'title': title,
      'pageNumber': pageNumber,
      'chunkOrder': chunkOrder,
      'sectionTitle': sectionTitle,
    });
  }
}

class PdfDocumentMetadata {
  const PdfDocumentMetadata({
    required this.documentId,
    required this.title,
    required this.pageCount,
    required this.isEncrypted,
  });

  final String documentId;
  final String title;
  final int pageCount;
  final bool isEncrypted;
}

class PdfSearchMatch {
  const PdfSearchMatch({
    required this.pageNumber,
    required this.text,
    required this.bounds,
  });

  final int pageNumber;
  final String text;
  final Rect bounds;
}

class PdfExtractionError {
  const PdfExtractionError(this.message);

  final String message;
}

enum AnnotationKind { highlight, note }

class DocumentIdentity {
  const DocumentIdentity({
    required this.fingerprint,
    required this.path,
    required this.title,
    required this.byteLength,
    required this.modifiedAt,
    required this.pageCount,
    required this.isEncrypted,
  });

  factory DocumentIdentity.fromJson(Map<String, dynamic> json) {
    return DocumentIdentity(
      fingerprint: json['fingerprint'] as String,
      path: json['path'] as String,
      title: json['title'] as String,
      byteLength: json['byteLength'] as int,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      pageCount: json['pageCount'] as int?,
      isEncrypted: json['isEncrypted'] as bool? ?? false,
    );
  }

  final String fingerprint;
  final String path;
  final String title;
  final int byteLength;
  final DateTime modifiedAt;
  final int? pageCount;
  final bool isEncrypted;

  DocumentIdentity copyWith({
    String? path,
    String? title,
    int? byteLength,
    DateTime? modifiedAt,
    int? pageCount,
    bool? isEncrypted,
  }) {
    return DocumentIdentity(
      fingerprint: fingerprint,
      path: path ?? this.path,
      title: title ?? this.title,
      byteLength: byteLength ?? this.byteLength,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      pageCount: pageCount ?? this.pageCount,
      isEncrypted: isEncrypted ?? this.isEncrypted,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'fingerprint': fingerprint,
    'path': path,
    'title': title,
    'byteLength': byteLength,
    'modifiedAt': modifiedAt.toIso8601String(),
    'pageCount': pageCount,
    'isEncrypted': isEncrypted,
  };
}

class DocumentBookmark {
  const DocumentBookmark({
    required this.id,
    required this.pageNumber,
    required this.label,
    required this.createdAt,
  });

  factory DocumentBookmark.fromJson(Map<String, dynamic> json) {
    return DocumentBookmark(
      id: json['id'] as String,
      pageNumber: json['pageNumber'] as int,
      label: json['label'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final int pageNumber;
  final String label;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'pageNumber': pageNumber,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
  };
}

class DocumentAnnotation {
  const DocumentAnnotation({
    required this.id,
    required this.kind,
    required this.pageNumber,
    required this.pageRects,
    required this.selectedText,
    required this.note,
    required this.colorValue,
    required this.createdAt,
    DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? createdAt;

  factory DocumentAnnotation.fromJson(Map<String, dynamic> json) {
    final DateTime createdAt = DateTime.parse(json['createdAt'] as String);
    return DocumentAnnotation(
      id: json['id'] as String,
      kind: AnnotationKind.values.byName(json['kind'] as String),
      pageNumber: json['pageNumber'] as int,
      pageRects: (json['pageRects'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic item) {
            final Map<String, dynamic> rect = item as Map<String, dynamic>;
            return Rect.fromLTWH(
              (rect['left'] as num).toDouble(),
              (rect['top'] as num).toDouble(),
              (rect['width'] as num).toDouble(),
              (rect['height'] as num).toDouble(),
            );
          })
          .toList(growable: false),
      selectedText: json['selectedText'] as String? ?? '',
      note: json['note'] as String?,
      colorValue: json['colorValue'] as int? ?? 0x66FFD54F,
      createdAt: createdAt,
      modifiedAt:
          DateTime.tryParse(json['modifiedAt'] as String? ?? '') ?? createdAt,
    );
  }

  final String id;
  final AnnotationKind kind;
  final int pageNumber;
  final List<Rect> pageRects;
  final String selectedText;
  final String? note;
  final int colorValue;
  final DateTime createdAt;
  final DateTime modifiedAt;

  DocumentAnnotation copyWith({String? note, bool clearNote = false}) {
    return DocumentAnnotation(
      id: id,
      kind: kind,
      pageNumber: pageNumber,
      pageRects: pageRects,
      selectedText: selectedText,
      note: clearNote ? null : note ?? this.note,
      colorValue: colorValue,
      createdAt: createdAt,
      modifiedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'pageNumber': pageNumber,
    'pageRects': pageRects
        .map(
          (Rect rect) => <String, double>{
            'left': rect.left,
            'top': rect.top,
            'width': rect.width,
            'height': rect.height,
          },
        )
        .toList(growable: false),
    'selectedText': selectedText,
    'note': note,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
  };
}

class OcrWordData {
  const OcrWordData({
    required this.text,
    required this.confidence,
    required this.bounds,
  });

  factory OcrWordData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> bounds = json['bounds'] as Map<String, dynamic>;
    return OcrWordData(
      text: json['text'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      bounds: Rect.fromLTRB(
        (bounds['left'] as num).toDouble(),
        (bounds['top'] as num).toDouble(),
        (bounds['right'] as num).toDouble(),
        (bounds['bottom'] as num).toDouble(),
      ),
    );
  }

  final String text;
  final double confidence;
  final Rect bounds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'confidence': confidence,
    'bounds': <String, double>{
      'left': bounds.left,
      'top': bounds.top,
      'right': bounds.right,
      'bottom': bounds.bottom,
    },
  };
}

class OcrPageData {
  const OcrPageData({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.modelId,
    required this.words,
  });

  factory OcrPageData.fromJson(Map<String, dynamic> json) {
    return OcrPageData(
      pageNumber: json['pageNumber'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      modelId: json['modelId'] as String,
      words: (json['words'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) =>
                OcrWordData.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final int pageNumber;
  final int width;
  final int height;
  final String modelId;
  final List<OcrWordData> words;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'pageNumber': pageNumber,
    'width': width,
    'height': height,
    'modelId': modelId,
    'words': words
        .map((OcrWordData word) => word.toJson())
        .toList(growable: false),
  };
}

class DocumentMetadata {
  const DocumentMetadata({
    required this.identity,
    required this.bookmarks,
    required this.annotations,
    this.ocrPages = const <int, OcrPageData>{},
  });

  factory DocumentMetadata.empty(DocumentIdentity identity) {
    return DocumentMetadata(
      identity: identity,
      bookmarks: const <DocumentBookmark>[],
      annotations: const <DocumentAnnotation>[],
    );
  }

  factory DocumentMetadata.fromJson(Map<String, dynamic> json) {
    return DocumentMetadata(
      identity: DocumentIdentity.fromJson(
        json['identity'] as Map<String, dynamic>,
      ),
      bookmarks: (json['bookmarks'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) =>
                DocumentBookmark.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      annotations: (json['annotations'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic item) =>
                DocumentAnnotation.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      ocrPages: <int, OcrPageData>{
        for (final dynamic item
            in json['ocrPages'] as List<dynamic>? ?? const <dynamic>[])
          (item as Map<String, dynamic>)['pageNumber'] as int:
              OcrPageData.fromJson(item),
      },
    );
  }

  final DocumentIdentity identity;
  final List<DocumentBookmark> bookmarks;
  final List<DocumentAnnotation> annotations;
  final Map<int, OcrPageData> ocrPages;

  DocumentMetadata copyWith({
    DocumentIdentity? identity,
    List<DocumentBookmark>? bookmarks,
    List<DocumentAnnotation>? annotations,
    Map<int, OcrPageData>? ocrPages,
  }) {
    return DocumentMetadata(
      identity: identity ?? this.identity,
      bookmarks: bookmarks ?? this.bookmarks,
      annotations: annotations ?? this.annotations,
      ocrPages: ocrPages ?? this.ocrPages,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'identity': identity.toJson(),
    'bookmarks': bookmarks
        .map((DocumentBookmark item) => item.toJson())
        .toList(growable: false),
    'annotations': annotations
        .map((DocumentAnnotation item) => item.toJson())
        .toList(growable: false),
    'ocrPages': ocrPages.values
        .map((OcrPageData page) => page.toJson())
        .toList(growable: false),
  };
}
