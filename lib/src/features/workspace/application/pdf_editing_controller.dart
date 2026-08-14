import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfTextSelection;

import '../domain/pdf_edit_intent.dart';
import '../domain/pdf_edit_session.dart';
import '../domain/pdf_native_edit_types.dart';
import '../domain/pdf_page_object.dart';
import '../domain/pdf_text_types.dart';
import '../infrastructure/pdf_native_edit_coordinator.dart';
import '../infrastructure/pdf_preview_document_controller.dart';
import '../infrastructure/pdf_text_engine.dart';
import '../infrastructure/pdf_edit_save_service.dart';
import 'pdf_edit_intent_dispatcher.dart';

final class PdfEditingController extends ChangeNotifier {
  PdfEditingController({
    String Function()? commandId,
    PdfTextEngine? engine,
    PdfEditSaveService? saveService,
    PdfPreviewDocumentController? previewController,
    PdfNativeEditCoordinator? nativeCoordinator,
  }) : _commandId = commandId ?? _defaultCommandId {
    _engine = engine;
    _saveService = saveService;
    _preview =
        previewController ??
        (engine == null ? null : PdfPreviewDocumentController(mutator: engine));
    _native =
        nativeCoordinator ??
        (engine == null ? null : PdfNativeEditCoordinator(mutator: engine));
    _dispatcher = PdfEditIntentDispatcher(
      readSession: _sessionForDocument,
      writeSession: _replaceByDocument,
      commandId: _commandId,
    );
  }

  final String Function() _commandId;
  late final PdfTextEngine? _engine;
  late final PdfEditSaveService? _saveService;
  late final PdfPreviewDocumentController? _preview;
  late final PdfNativeEditCoordinator? _native;
  final Map<String, PdfDocument> _documentsByTab = <String, PdfDocument>{};
  final Map<String, PdfEditingSession> _sessions =
      <String, PdfEditingSession>{};
  final Map<String, int> _discoveryGenerations = <String, int>{};
  final Map<String, int> _editRevisions = <String, int>{};
  late final PdfEditIntentDispatcher _dispatcher;

  Map<String, PdfEditingSession> get sessionsByTabId =>
      UnmodifiableMapView<String, PdfEditingSession>(_sessions);

  void registerSession(String tabId, PdfEditingSession session) {
    _sessions[tabId] = session;
    notifyListeners();
  }

  void registerDocument(String tabId, PdfDocument document) {
    _documentsByTab[tabId] = document;
  }

  void replaceSession(String tabId, PdfEditingSession session) {
    if (!_sessions.containsKey(tabId)) {
      throw StateError('No PDF edit session for $tabId.');
    }
    _sessions[tabId] = session;
    notifyListeners();
  }

  void markSaved(String tabId) {
    replaceSession(tabId, sessionFor(tabId).markSaved());
  }

  Future<PdfSaveOutcome> save(String tabId, String path) async {
    final service = _saveService;
    if (service == null) throw const PdfNativeEditingUnavailableFailure();
    final session = sessionFor(tabId);
    final document = _documentsByTab[tabId];
    if (document != null) await _preview?.clear(document);
    if (session.overflowingLocators.isNotEmpty) {
      throw PdfTextOverflowFailure(locator: session.overflowingLocators.first);
    }
    final outcome = await service.save(
      PdfSaveRequest(
        path: path,
        sourceRevision: session.sourceRevision,
        draft: session,
      ),
    );
    replaceSession(
      tabId,
      session.withSourceRevision(outcome.newRevision).markSaved(),
    );
    return outcome;
  }

  void removeSession(String tabId) {
    final document = _documentsByTab.remove(tabId);
    if (document != null) {
      unawaited(_preview?.clear(document));
      _native?.forgetDocument(document);
    }
    _editRevisions.remove(tabId);
    if (_sessions.remove(tabId) != null) notifyListeners();
  }

  PdfEditingSession sessionFor(String tabId) {
    final session = _sessions[tabId];
    if (session == null) throw StateError('No PDF edit session for $tabId.');
    return session;
  }

  Future<PdfEditResult> dispatch(
    PdfEditIntent intent, {
    required PdfCommandProvenance provenance,
  }) {
    if (intent.affectedLocators.isNotEmpty) {
      for (final entry in _sessions.entries) {
        if (entry.value.documentId == intent.documentId &&
            _documentsByTab.containsKey(entry.key)) {
          return dispatchAndProject(
            tabId: entry.key,
            intent: intent,
            provenance: provenance,
          );
        }
      }
    }
    return _dispatcher.dispatch(intent, provenance: provenance);
  }

  Future<PdfEditResult> dispatchAndProject({
    required String tabId,
    required PdfEditIntent intent,
    required PdfCommandProvenance provenance,
  }) async {
    final before = sessionFor(tabId);
    final result = await _dispatcher.dispatch(intent, provenance: provenance);
    if (!result.isSuccess || result.affectedLocators.isEmpty) return result;
    try {
      await _projectBlocks(tabId, sessionFor(tabId), result.affectedLocators);
      return result;
    } catch (error, stackTrace) {
      replaceSession(tabId, before);
      try {
        await _projectBlocks(tabId, before, result.affectedLocators);
      } catch (_) {
        // Preserve the original projection failure for the caller.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<PdfEditResult> undo(String tabId, {PdfDocument? document}) async {
    final session = sessionFor(tabId);
    if (document != null) registerDocument(tabId, document);
    final affected = session.canUndo
        ? session.commands[session.cursor - 1].affectedLocators
        : const <PdfTextBlockLocator>[];
    final result = await _dispatchAndProjectAffected(
      UndoPdfEditIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
      ),
      tabId: tabId,
      provenance: PdfCommandProvenance.manual,
      affectedLocators: affected,
    );
    final target = document ?? _documentsByTab[tabId];
    if (result.isSuccess && target != null) {
      await _preview?.rebuildFromSession(target, sessionFor(tabId));
    }
    return result;
  }

  Future<PdfEditResult> redo(String tabId, {PdfDocument? document}) async {
    final session = sessionFor(tabId);
    if (document != null) registerDocument(tabId, document);
    final affected = session.canRedo
        ? session.commands[session.cursor].affectedLocators
        : const <PdfTextBlockLocator>[];
    final result = await _dispatchAndProjectAffected(
      RedoPdfEditIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
      ),
      tabId: tabId,
      provenance: PdfCommandProvenance.manual,
      affectedLocators: affected,
    );
    final target = document ?? _documentsByTab[tabId];
    if (result.isSuccess && target != null) {
      await _preview?.rebuildFromSession(target, sessionFor(tabId));
    }
    return result;
  }

  Future<void> enterTextMode(
    String tabId,
    PdfDocument document,
    int currentPage,
  ) async {
    registerDocument(tabId, document);
    final session = sessionFor(tabId);
    await dispatch(
      SetPdfEditingModeIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
        mode: PdfEditingMode.object,
      ),
      provenance: PdfCommandProvenance.manual,
    );
    final generation = (_discoveryGenerations[tabId] ?? 0) + 1;
    _discoveryGenerations[tabId] = generation;
    await _inspectPages(tabId, document, <int>[currentPage], generation);
    final neighbors = <int>[
      if (currentPage > 1) currentPage - 1,
      if (currentPage < document.pages.length) currentPage + 1,
    ];
    if (neighbors.isNotEmpty) {
      unawaited(
        _inspectPages(
          tabId,
          document,
          neighbors,
          generation,
        ).catchError((_) {}),
      );
    }
  }

  Future<void> leaveTextMode(String tabId, {PdfDocument? document}) async {
    _discoveryGenerations[tabId] = (_discoveryGenerations[tabId] ?? 0) + 1;
    final session = sessionFor(tabId);
    final target = document ?? _documentsByTab[tabId];
    if (target != null) await _preview?.clear(target);
    await dispatch(
      SetPdfEditingModeIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
        mode: PdfEditingMode.reading,
      ),
      provenance: PdfCommandProvenance.manual,
    );
  }

  Future<void> selectTextBlock(
    String tabId,
    PdfDocument document,
    PdfTextBlockLocator locator,
  ) async {
    final session = sessionFor(tabId);
    final block = session.blocks.firstWhere(
      (candidate) => candidate.locator == locator,
      orElse: () => throw PdfStaleLocatorFailure(locator),
    );
    await _preview?.suppressText(document, block);
    replaceSession(
      tabId,
      session.withSelection(
        PdfTextSelection(locator: locator, range: const PdfTextRange(0, 0)),
      ),
    );
  }

  @Deprecated('Use selectTextBlock so native glyph suppression is awaited.')
  void selectBlock(String tabId, PdfTextBlockLocator locator) {
    final session = sessionFor(tabId);
    replaceSession(
      tabId,
      session.withSelection(
        PdfTextSelection(locator: locator, range: const PdfTextRange(0, 0)),
      ),
    );
  }

  Future<void> clearSelection(String tabId, {PdfDocument? document}) async {
    final target = document ?? _documentsByTab[tabId];
    if (target != null) await _preview?.restoreSuppressedText(target);
    replaceSession(tabId, sessionFor(tabId).withSelection(null));
  }

  Future<void> selectPageObject(
    String tabId,
    PdfPageObjectLocator locator,
  ) async {
    final session = sessionFor(tabId);
    if (!session.pageObjects.any((object) => object.locator == locator)) {
      throw PdfStalePageObjectLocatorFailure(locator);
    }
  }

  Future<void> previewTransform(
    String tabId,
    PdfDocument document,
    PdfPageObjectLocator locator,
    PdfTransform transform,
  ) async {
    final object = sessionFor(
      tabId,
    ).pageObjects.firstWhere((item) => item.locator == locator);
    await _preview?.previewTransform(document, object, transform);
  }

  Future<void> _inspectPages(
    String tabId,
    PdfDocument document,
    List<int> pageNumbers,
    int generation,
  ) async {
    final engine = _engine;
    if (engine == null) throw const PdfNativeEditingUnavailableFailure();
    final session = sessionFor(tabId);
    final discovered = await engine.inspectPages(
      document: document,
      sourceRevision: session.sourceRevision,
      pageNumbers: pageNumbers,
    );
    final pageObjects = await engine.inspectPageObjects(
      document: document,
      sourceRevision: session.sourceRevision,
      pageNumbers: pageNumbers,
    );
    if (_discoveryGenerations[tabId] != generation ||
        !_sessions.containsKey(tabId)) {
      return;
    }
    final pages = pageNumbers.toSet();
    replaceSession(
      tabId,
      sessionFor(tabId)
          .withBlocks(<PdfTextBlock>[
            ...sessionFor(tabId).blocks.where(
              (block) => !pages.contains(block.locator.pageNumber),
            ),
            ...discovered,
          ])
          .withPageObjects(<PdfPageObject>[
            ...sessionFor(tabId).pageObjects.where(
              (object) => !pages.contains(object.locator.pageNumber),
            ),
            ...pageObjects,
          ]),
    );
  }

  Future<PdfEditResult> _dispatchAndProjectAffected(
    PdfEditIntent intent, {
    required String tabId,
    required PdfCommandProvenance provenance,
    required List<PdfTextBlockLocator> affectedLocators,
  }) async {
    final before = sessionFor(tabId);
    final result = await _dispatcher.dispatch(intent, provenance: provenance);
    if (!result.isSuccess ||
        affectedLocators.isEmpty ||
        _native == null ||
        !_documentsByTab.containsKey(tabId)) {
      return result;
    }
    try {
      await _projectBlocks(tabId, sessionFor(tabId), affectedLocators);
      return result;
    } catch (error, stackTrace) {
      replaceSession(tabId, before);
      try {
        await _projectBlocks(tabId, before, affectedLocators);
      } catch (_) {
        // Preserve the original projection failure for the caller.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _projectBlocks(
    String tabId,
    PdfEditingSession session,
    List<PdfTextBlockLocator> locators,
  ) async {
    final coordinator = _native;
    final document = _documentsByTab[tabId];
    if (coordinator == null || document == null) {
      throw const PdfNativeEditingUnavailableFailure();
    }
    for (final locator in locators.toSet()) {
      final block = session.blocks.firstWhere(
        (candidate) => candidate.locator == locator,
        orElse: () => throw PdfStaleLocatorFailure(locator),
      );
      final revision = (_editRevisions[tabId] ?? 0) + 1;
      _editRevisions[tabId] = revision;
      await coordinator.projectBlock(
        document,
        PdfNativeProjectionRequest(
          documentRevision: session.sourceRevision,
          editRevision: revision,
          block: block,
        ),
      );
    }
  }

  PdfEditingSession _sessionForDocument(String documentId) {
    for (final session in _sessions.values) {
      if (session.documentId == documentId) return session;
    }
    throw StateError('No PDF edit session for $documentId.');
  }

  void _replaceByDocument(PdfEditingSession next) {
    final tabs = _sessions.entries
        .where((entry) => entry.value.documentId == next.documentId)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (tabs.isEmpty) {
      throw StateError('No PDF edit session for ${next.documentId}.');
    }
    for (final tabId in tabs) {
      _sessions[tabId] = next;
    }
    notifyListeners();
  }

  static var _nextId = 0;
  static String _defaultCommandId() =>
      'pdf-edit-${DateTime.now().microsecondsSinceEpoch}-${++_nextId}';
}
