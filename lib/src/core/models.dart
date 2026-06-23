import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

enum SidebarPane { thumbnails, outline }

enum DocumentIndexStatus { idle, queued, indexing, indexed, unavailable, failed }

enum AiRuntimePhase {
  idle,
  restoringInference,
  restoringEmbedding,
  loadingInference,
  preparingGrounding,
  indexing,
  retrieving,
  generating,
  failed,
}

enum DownloadTaskStatus {
  idle,
  running,
  paused,
  validating,
  failed,
  completed,
}

enum ModelCatalogType { inference, embedding }

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
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
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
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
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
      documentId: documentId,
      filePath: filePath,
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
      installedPath:
          clearInstalledPath ? null : installedPath ?? this.installedPath,
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
      errorMessage:
          clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      installedPath:
          clearInstalledPath ? null : installedPath ?? this.installedPath,
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
    required this.inferenceReady,
    required this.embeddingReady,
    required this.vectorStoreReady,
    required this.chatBusy,
    required this.activityPhase,
    required this.statusMessage,
    required this.messages,
    required this.useCurrentDocumentScope,
    required this.lastRetrievalSnippets,
    required this.activeInferenceModelId,
    required this.activeEmbeddingModelId,
  });

  final bool inferenceReady;
  final bool embeddingReady;
  final bool vectorStoreReady;
  final bool chatBusy;
  final AiRuntimePhase activityPhase;
  final String statusMessage;
  final List<ComposerMessage> messages;
  final bool useCurrentDocumentScope;
  final List<CitationSnippet> lastRetrievalSnippets;
  final String? activeInferenceModelId;
  final String? activeEmbeddingModelId;

  factory AiWorkspaceState.initial() => const AiWorkspaceState(
        inferenceReady: false,
        embeddingReady: false,
        vectorStoreReady: false,
        chatBusy: false,
        activityPhase: AiRuntimePhase.idle,
        statusMessage: 'Install a model to unlock local AI features.',
        messages: <ComposerMessage>[],
        useCurrentDocumentScope: true,
        lastRetrievalSnippets: <CitationSnippet>[],
        activeInferenceModelId: null,
        activeEmbeddingModelId: null,
      );

  AiWorkspaceState copyWith({
    bool? inferenceReady,
    bool? embeddingReady,
    bool? vectorStoreReady,
    bool? chatBusy,
    AiRuntimePhase? activityPhase,
    String? statusMessage,
    List<ComposerMessage>? messages,
    bool? useCurrentDocumentScope,
    List<CitationSnippet>? lastRetrievalSnippets,
    String? activeInferenceModelId,
    bool clearActiveInferenceModelId = false,
    String? activeEmbeddingModelId,
    bool clearActiveEmbeddingModelId = false,
  }) {
    return AiWorkspaceState(
      inferenceReady: inferenceReady ?? this.inferenceReady,
      embeddingReady: embeddingReady ?? this.embeddingReady,
      vectorStoreReady: vectorStoreReady ?? this.vectorStoreReady,
      chatBusy: chatBusy ?? this.chatBusy,
      activityPhase: activityPhase ?? this.activityPhase,
      statusMessage: statusMessage ?? this.statusMessage,
      messages: messages ?? this.messages,
      useCurrentDocumentScope:
          useCurrentDocumentScope ?? this.useCurrentDocumentScope,
      lastRetrievalSnippets:
          lastRetrievalSnippets ?? this.lastRetrievalSnippets,
      activeInferenceModelId: clearActiveInferenceModelId
          ? null
          : activeInferenceModelId ?? this.activeInferenceModelId,
      activeEmbeddingModelId: clearActiveEmbeddingModelId
          ? null
          : activeEmbeddingModelId ?? this.activeEmbeddingModelId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'inferenceReady': inferenceReady,
        'embeddingReady': embeddingReady,
        'vectorStoreReady': vectorStoreReady,
        'activityPhase': activityPhase.name,
        'statusMessage': statusMessage,
        'useCurrentDocumentScope': useCurrentDocumentScope,
        'activeInferenceModelId': activeInferenceModelId,
        'activeEmbeddingModelId': activeEmbeddingModelId,
      };

  factory AiWorkspaceState.fromJson(Map<String, dynamic> json) {
    return AiWorkspaceState.initial().copyWith(
      inferenceReady: json['inferenceReady'] as bool? ?? false,
      embeddingReady: json['embeddingReady'] as bool? ?? false,
      vectorStoreReady: json['vectorStoreReady'] as bool? ?? false,
      activityPhase: AiRuntimePhase.idle,
      statusMessage: json['statusMessage'] as String?,
      useCurrentDocumentScope:
          json['useCurrentDocumentScope'] as bool? ?? true,
      activeInferenceModelId: json['activeInferenceModelId'] as String?,
      activeEmbeddingModelId: json['activeEmbeddingModelId'] as String?,
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

  ComposerMessage copyWith({
    String? text,
    List<CitationSnippet>? citations,
  }) {
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
