import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfTextSelection;

import '../domain/pdf_edit_intent.dart';
import '../domain/pdf_edit_session.dart';
import '../domain/pdf_text_types.dart';
import '../infrastructure/pdf_text_engine.dart';
import 'pdf_edit_intent_dispatcher.dart';

final class PdfEditingController extends ChangeNotifier {
  PdfEditingController({String Function()? commandId, PdfTextEngine? engine})
    : _commandId = commandId ?? _defaultCommandId {
    _engine = engine;
    _dispatcher = PdfEditIntentDispatcher(
      readSession: _sessionForDocument,
      writeSession: _replaceByDocument,
      commandId: _commandId,
    );
  }

  final String Function() _commandId;
  late final PdfTextEngine? _engine;
  final Map<String, PdfEditingSession> _sessions =
      <String, PdfEditingSession>{};
  final Map<String, int> _discoveryGenerations = <String, int>{};
  late final PdfEditIntentDispatcher _dispatcher;

  Map<String, PdfEditingSession> get sessionsByTabId =>
      UnmodifiableMapView<String, PdfEditingSession>(_sessions);

  void registerSession(String tabId, PdfEditingSession session) {
    _sessions[tabId] = session;
    notifyListeners();
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

  void removeSession(String tabId) {
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
  }) => _dispatcher.dispatch(intent, provenance: provenance);

  Future<PdfEditResult> undo(String tabId) {
    final session = sessionFor(tabId);
    return dispatch(
      UndoPdfEditIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
      ),
      provenance: PdfCommandProvenance.manual,
    );
  }

  Future<PdfEditResult> redo(String tabId) {
    final session = sessionFor(tabId);
    return dispatch(
      RedoPdfEditIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
      ),
      provenance: PdfCommandProvenance.manual,
    );
  }

  Future<void> enterTextMode(
    String tabId,
    PdfDocument document,
    int currentPage,
  ) async {
    final session = sessionFor(tabId);
    await dispatch(
      SetPdfEditingModeIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
        mode: PdfEditingMode.text,
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

  Future<void> leaveTextMode(String tabId) async {
    _discoveryGenerations[tabId] = (_discoveryGenerations[tabId] ?? 0) + 1;
    final session = sessionFor(tabId);
    await dispatch(
      SetPdfEditingModeIntent(
        documentId: session.documentId,
        documentRevision: session.revision,
        mode: PdfEditingMode.reading,
      ),
      provenance: PdfCommandProvenance.manual,
    );
  }

  void selectBlock(String tabId, PdfTextBlockLocator locator) {
    final session = sessionFor(tabId);
    replaceSession(
      tabId,
      session.withSelection(
        PdfTextSelection(locator: locator, range: const PdfTextRange(0, 0)),
      ),
    );
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
    if (_discoveryGenerations[tabId] != generation ||
        !_sessions.containsKey(tabId)) {
      return;
    }
    final pages = pageNumbers.toSet();
    replaceSession(
      tabId,
      sessionFor(tabId).withBlocks(<PdfTextBlock>[
        ...sessionFor(
          tabId,
        ).blocks.where((block) => !pages.contains(block.locator.pageNumber)),
        ...discovered,
      ]),
    );
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
