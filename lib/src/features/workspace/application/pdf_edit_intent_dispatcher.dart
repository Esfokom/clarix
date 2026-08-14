// ignore_for_file: prefer_initializing_formals

import '../domain/pdf_edit_command.dart';
import '../domain/pdf_edit_intent.dart';
import '../domain/pdf_edit_session.dart';
import '../domain/pdf_text_case.dart';
import '../domain/pdf_text_layout.dart';
import '../domain/pdf_text_types.dart';

typedef PdfSessionReader = PdfEditingSession Function(String documentId);
typedef PdfSessionWriter = void Function(PdfEditingSession session);

final class PdfEditIntentDispatcher {
  PdfEditIntentDispatcher({
    required PdfSessionReader readSession,
    required PdfSessionWriter writeSession,
    required String Function() commandId,
  }) : _readSession = readSession,
       _writeSession = writeSession,
       _commandId = commandId;

  final PdfSessionReader _readSession;
  final PdfSessionWriter _writeSession;
  final String Function() _commandId;

  Future<PdfEditResult> dispatch(
    PdfEditIntent intent, {
    required PdfCommandProvenance provenance,
  }) async {
    final session = _readSession(intent.documentId);
    if (intent.documentRevision != session.revision) {
      return PdfEditResult.failure(
        PdfRevisionConflictFailure(
          expected: session.revision,
          actual: intent.documentRevision,
        ),
      );
    }
    try {
      if (intent case SetPdfEditingModeIntent(:final mode)) {
        final next = session.withMode(mode);
        _writeSession(next);
        return _result(next, const <String>[], intent.affectedLocators);
      }
      if (intent case SetPdfCaseMatchingIntent(:final enabled)) {
        final next = session.withCaseMatching(enabled);
        _writeSession(next);
        return _result(next, const <String>[], intent.affectedLocators);
      }
      if (intent is UndoPdfEditIntent) {
        final commandId = session.canUndo
            ? session.commands[session.cursor - 1].id
            : null;
        final next = _reflow(session.undo());
        _writeSession(next);
        return _result(
          next,
          commandId == null ? const <String>[] : <String>[commandId],
          const <PdfTextBlockLocator>[],
        );
      }
      if (intent is RedoPdfEditIntent) {
        final commandId = session.canRedo
            ? session.commands[session.cursor].id
            : null;
        final next = _reflow(session.redo());
        _writeSession(next);
        return _result(
          next,
          commandId == null ? const <String>[] : <String>[commandId],
          const <PdfTextBlockLocator>[],
        );
      }
      if (intent is SavePdfEditsIntent) {
        if (session.overflowingLocators.isNotEmpty) {
          return PdfEditResult.failure(
            PdfTextOverflowFailure(locator: session.overflowingLocators.first),
          );
        }
        return _result(
          session,
          const <String>[],
          const <PdfTextBlockLocator>[],
        );
      }

      final command = _createCommand(session, intent, provenance);
      final next = _reflow(session.applyCommand(command));
      _writeSession(next);
      return _result(next, <String>[command.id], command.affectedLocators);
    } on PdfEditFailure catch (failure) {
      return PdfEditResult.failure(failure);
    }
  }

  PdfEditingSession _reflow(PdfEditingSession session) => session.withBlocks(
    session.blocks
        .map((block) {
          if (block.text.isEmpty || block.runs.isEmpty) {
            return block.copyWith(overflow: false);
          }
          final style = block.styleAt(0);
          final result = const PdfTextLayoutEngine().layout(
            text: block.text,
            bounds: block.bounds,
            style: style,
            metrics: PdfMonospaceTextMetrics(
              advance: style.fontSize * 0.5,
              lineHeight: style.fontSize * 0.8,
            ),
          );
          return block.copyWith(overflow: result.overflow);
        })
        .toList(growable: false),
  );

  PdfEditCommand _createCommand(
    PdfEditingSession session,
    PdfEditIntent intent,
    PdfCommandProvenance provenance,
  ) {
    final id = _commandId();
    return switch (intent) {
      ReplacePdfTextIntent(
        :final locator,
        :final range,
        :final replacement,
        :final caseMatching,
        :final coalescingKey,
      ) =>
        _replaceCommand(
          session,
          id,
          provenance,
          locator,
          range,
          replacement,
          caseMatching,
          coalescingKey,
        ),
      FormatPdfTextIntent(:final locator, :final range, :final patch) =>
        _formatCommand(session, id, provenance, locator, range, patch),
      MovePdfTextBlockIntent(:final locator, :final bounds) =>
        MovePdfTextBlockCommand(
          id: id,
          provenance: provenance,
          locator: locator,
          before: _block(session, locator).bounds,
          after: bounds,
        ),
      ResizePdfTextBlockIntent(:final locator, :final bounds) =>
        ResizePdfTextBlockCommand(
          id: id,
          provenance: provenance,
          locator: locator,
          before: _block(session, locator).bounds,
          after: bounds,
        ),
      ChangePdfBookmarkIntent(:final before, :final after) =>
        ChangePdfBookmarkCommand(
          id: id,
          provenance: provenance,
          before: before,
          after: after,
        ),
      ChangePdfHighlightIntent(:final before, :final after) =>
        ChangePdfHighlightCommand(
          id: id,
          provenance: provenance,
          before: before,
          after: after,
        ),
      ChangePdfMetadataIntent(:final bookmarks, :final highlights) =>
        _metadataCommand(session, id, provenance, bookmarks, highlights),
      _ => throw StateError('The intent does not create an edit command.'),
    };
  }

  CompoundPdfEditCommand _metadataCommand(
    PdfEditingSession session,
    String id,
    PdfCommandProvenance provenance,
    List<PdfBookmarkSnapshot> bookmarks,
    List<PdfHighlightSnapshot> highlights,
  ) {
    final children = <PdfEditCommand>[];
    final bookmarkIds = <String>{
      ...session.bookmarks.map((item) => item.id),
      ...bookmarks.map((item) => item.id),
    };
    for (final bookmarkId in bookmarkIds) {
      final before = _bookmarkById(session.bookmarks, bookmarkId);
      final after = _bookmarkById(bookmarks, bookmarkId);
      if (before != after) {
        children.add(
          ChangePdfBookmarkCommand(
            id: _commandId(),
            provenance: provenance,
            before: before,
            after: after,
          ),
        );
      }
    }
    final highlightIds = <String>{
      ...session.highlights.map((item) => item.id),
      ...highlights.map((item) => item.id),
    };
    for (final highlightId in highlightIds) {
      final before = _highlightById(session.highlights, highlightId);
      final after = _highlightById(highlights, highlightId);
      if (before != after) {
        children.add(
          ChangePdfHighlightCommand(
            id: _commandId(),
            provenance: provenance,
            before: before,
            after: after,
          ),
        );
      }
    }
    return CompoundPdfEditCommand(
      id: id,
      provenance: provenance,
      summary: 'Change PDF metadata',
      children: children,
    );
  }

  ReplacePdfTextCommand _replaceCommand(
    PdfEditingSession session,
    String id,
    PdfCommandProvenance provenance,
    PdfTextBlockLocator locator,
    PdfTextRange range,
    String replacement,
    bool caseMatching,
    String? coalescingKey,
  ) {
    final block = _block(session, locator);
    block.validateOperation(PdfTextCapability.replace);
    if (range.start < 0 ||
        range.end < range.start ||
        range.end > block.text.length) {
      throw PdfInvalidTextRangeFailure(
        range: range,
        textLength: block.text.length,
      );
    }
    final source = block.text.substring(range.start, range.end);
    var casingSource = source;
    if (casingSource.isEmpty && coalescingKey != null && session.cursor > 0) {
      final previous = session.commands[session.cursor - 1];
      if (previous is ReplacePdfTextCommand &&
          previous.locator == locator &&
          previous.coalescingKey == coalescingKey) {
        casingSource = previous.before;
      }
    }
    final effectiveReplacement =
        caseMatching && session.caseMatching && casingSource.isNotEmpty
        ? matchReplacementCase(casingSource, replacement)
        : replacement;
    return ReplacePdfTextCommand(
      id: id,
      provenance: provenance,
      locator: locator,
      before: source,
      after: effectiveReplacement,
      range: range,
      coalescingKey: coalescingKey,
    );
  }

  FormatPdfTextCommand _formatCommand(
    PdfEditingSession session,
    String id,
    PdfCommandProvenance provenance,
    PdfTextBlockLocator locator,
    PdfTextRange range,
    PdfTextStylePatch patch,
  ) {
    final block = _block(session, locator);
    block.validateOperation(PdfTextCapability.format);
    final before = block.styleAt(range.start);
    return FormatPdfTextCommand(
      id: id,
      provenance: provenance,
      locator: locator,
      range: range,
      before: before,
      after: patch.applyTo(before),
    );
  }

  PdfTextBlock _block(PdfEditingSession session, PdfTextBlockLocator locator) {
    for (final block in session.blocks) {
      if (block.locator == locator) return block;
    }
    throw PdfStaleLocatorFailure(locator);
  }

  PdfEditResult _result(
    PdfEditingSession session,
    List<String> commandIds,
    List<PdfTextBlockLocator> affectedLocators,
  ) => PdfEditResult.applied(
    revision: session.revision,
    commandIds: commandIds,
    affectedLocators: affectedLocators,
    isDirty: session.isDirty,
  );
}

PdfBookmarkSnapshot? _bookmarkById(
  List<PdfBookmarkSnapshot> bookmarks,
  String id,
) {
  for (final bookmark in bookmarks) {
    if (bookmark.id == id) return bookmark;
  }
  return null;
}

PdfHighlightSnapshot? _highlightById(
  List<PdfHighlightSnapshot> highlights,
  String id,
) {
  for (final highlight in highlights) {
    if (highlight.id == id) return highlight;
  }
  return null;
}
