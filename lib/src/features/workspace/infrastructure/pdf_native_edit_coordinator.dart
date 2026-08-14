import 'dart:collection';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../domain/pdf_native_edit_types.dart';
import '../domain/pdf_text_types.dart';
import 'pdf_text_engine.dart';

typedef PdfNativePageReloader =
    Future<void> Function(PdfDocument document, List<int> pageNumbers);

final class PdfNativeEditCoordinator {
  PdfNativeEditCoordinator({
    required this.mutator,
    PdfNativePageReloader? reloadPages,
  }) : _reloadPages = reloadPages ?? _reloadDocumentPages;

  final PdfLiveDocumentMutator mutator;
  final PdfNativePageReloader _reloadPages;
  final Map<PdfDocument, _DocumentProjectionState> _states = HashMap.identity();

  Future<void> projectBlock(
    PdfDocument document,
    PdfNativeProjectionRequest request,
  ) {
    final state = _states.putIfAbsent(document, _DocumentProjectionState.new);
    state.latestRequestedRevision = request.editRevision;
    return _serialized(state, () async {
      final nativeTarget = state.nativeResults[request.block.locator]?.block;
      final result = await mutator.projectTextBlock(
        document: document,
        request: nativeTarget == null
            ? request
            : request.withNativeTarget(nativeTarget),
      );
      if (!identical(_states[document], state) ||
          state.latestRequestedRevision != request.editRevision ||
          result.requestedRevision != request.editRevision ||
          result.appliedRevision != request.editRevision) {
        return;
      }

      state.latestResult = result;
      state.nativeResults[request.block.locator] = result;
      final pages = result.affectedPages.toSet().toList()..sort();
      await _reloadPages(document, pages);
    });
  }

  PdfNativeProjectionResult? latestResult(
    PdfDocument document, {
    PdfTextBlockLocator? logicalLocator,
  }) => logicalLocator == null
      ? _states[document]?.latestResult
      : _states[document]?.nativeResults[logicalLocator];

  Future<Uint8List> encode(PdfDocument document) {
    final state = _states.putIfAbsent(document, _DocumentProjectionState.new);
    return _serialized(
      state,
      () => mutator.encodeLiveDocument(document: document),
    );
  }

  void forgetDocument(PdfDocument document) {
    _states.remove(document);
  }

  Future<T> _serialized<T>(
    _DocumentProjectionState state,
    Future<T> Function() operation,
  ) {
    final next = state.queue.catchError((_) {}).then((_) => operation());
    state.queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  static Future<void> _reloadDocumentPages(
    PdfDocument document,
    List<int> pageNumbers,
  ) => document.reloadPages(pageNumbersToReload: pageNumbers);
}

final class _DocumentProjectionState {
  int? latestRequestedRevision;
  PdfNativeProjectionResult? latestResult;
  final Map<PdfTextBlockLocator, PdfNativeProjectionResult> nativeResults =
      <PdfTextBlockLocator, PdfNativeProjectionResult>{};
  Future<void> queue = Future<void>.value();
}
