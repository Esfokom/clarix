import 'dart:collection';

import 'package:pdfrx/pdfrx.dart';

import '../domain/pdf_edit_session.dart';
import '../domain/pdf_page_object.dart';
import '../domain/pdf_text_types.dart';
import 'pdf_text_engine.dart';

final class PdfPreviewDocumentController {
  PdfPreviewDocumentController({required PdfPreviewMutator mutator})
    : _mutator = mutator;

  final PdfPreviewMutator _mutator;
  final Map<PdfDocument, _PreviewState> _states = HashMap.identity();
  final Map<PdfDocument, Future<void>> _queues = HashMap.identity();

  Future<void> suppressText(PdfDocument document, PdfTextBlock block) =>
      _serialized(document, () async {
        final state = _states.putIfAbsent(document, _PreviewState.new);
        final previous = state.suppressedText;
        if (previous != null && previous.locator != block.locator) {
          await _mutator.setTextObjectsVisible(
            document: document,
            block: previous,
            visible: true,
          );
        }
        await _mutator.setTextObjectsVisible(
          document: document,
          block: block,
          visible: false,
        );
        state.suppressedText = block;
        await document.reloadPages(
          pageNumbersToReload: <int>[block.locator.pageNumber],
        );
      });

  Future<void> restoreSuppressedText(PdfDocument document) =>
      _serialized(document, () async {
        final block = _states[document]?.suppressedText;
        if (block == null) return;
        await _mutator.setTextObjectsVisible(
          document: document,
          block: block,
          visible: true,
        );
        _states[document]?.suppressedText = null;
        await document.reloadPages(
          pageNumbersToReload: <int>[block.locator.pageNumber],
        );
      });

  Future<void> previewTransform(
    PdfDocument document,
    PdfPageObject source,
    PdfTransform transform,
  ) => _serialized(document, () async {
    final state = _states.putIfAbsent(document, _PreviewState.new);
    state.originalTransforms.putIfAbsent(
      source.locator,
      () => source.transform,
    );
    await _mutator.setPageObjectPreviewTransform(
      document: document,
      locator: source.locator,
      transform: transform,
    );
    await document.reloadPages(
      pageNumbersToReload: <int>[source.locator.pageNumber],
    );
  });

  Future<void> rebuildFromSession(
    PdfDocument document,
    PdfEditingSession session,
  ) => _serialized(document, () async {
    final pages = <int>{};
    for (final object in session.pageObjects) {
      if (_states[document]?.originalTransforms.containsKey(object.locator) ??
          false) {
        await _mutator.setPageObjectPreviewTransform(
          document: document,
          locator: object.locator,
          transform: object.transform,
        );
        pages.add(object.locator.pageNumber);
      }
    }
    if (pages.isNotEmpty) {
      await document.reloadPages(pageNumbersToReload: pages.toList());
    }
  });

  Future<void> clear(PdfDocument document) => _serialized(document, () async {
    final state = _states.remove(document);
    if (state == null) return;
    final pages = <int>{};
    final block = state.suppressedText;
    if (block != null) {
      await _mutator.setTextObjectsVisible(
        document: document,
        block: block,
        visible: true,
      );
      pages.add(block.locator.pageNumber);
    }
    for (final entry in state.originalTransforms.entries) {
      await _mutator.setPageObjectPreviewTransform(
        document: document,
        locator: entry.key,
        transform: entry.value,
      );
      pages.add(entry.key.pageNumber);
    }
    if (pages.isNotEmpty) {
      await document.reloadPages(pageNumbersToReload: pages.toList());
    }
  });

  Future<void> _serialized(
    PdfDocument document,
    Future<void> Function() operation,
  ) {
    final previous = _queues[document] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    _queues[document] = next.whenComplete(() {
      if (identical(_queues[document], next)) _queues.remove(document);
    });
    return next;
  }
}

final class _PreviewState {
  PdfTextBlock? suppressedText;
  final Map<PdfPageObjectLocator, PdfTransform> originalTransforms =
      <PdfPageObjectLocator, PdfTransform>{};
}
