import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/pdf_edit_intent.dart';
import '../domain/pdf_edit_session.dart';
import '../domain/pdf_text_types.dart';
import 'pdf_edit_intent_dispatcher.dart';

final class PdfEditingController extends ChangeNotifier {
  PdfEditingController({String Function()? commandId})
    : _commandId = commandId ?? _defaultCommandId {
    _dispatcher = PdfEditIntentDispatcher(
      readSession: _sessionForDocument,
      writeSession: _replaceByDocument,
      commandId: _commandId,
    );
  }

  final String Function() _commandId;
  final Map<String, PdfEditingSession> _sessions =
      <String, PdfEditingSession>{};
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
