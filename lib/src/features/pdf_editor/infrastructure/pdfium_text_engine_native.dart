import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import '../domain/pdf_text_types.dart';
import '../domain/pdf_page_object.dart';
import '../domain/pdf_edit_session.dart';
import '../domain/pdf_native_edit_types.dart';
import '../domain/pdf_edit_command.dart';
import 'pdf_block_text.dart';
import 'pdf_text_block_grouper.dart';
import 'pdfium_page_object_path.dart';
import 'pdf_text_engine.dart';
import 'installed_font_catalog.dart';
import 'pdf_native_text_layout.dart';
import 'pdfium_worker_executor.dart';

part 'pdfium_text_engine_worker_helpers.dart';
part 'pdfium_text_engine_inspection.dart';

PdfTextEngine createPdfTextEngine() => const PdfiumTextEngine();

final class PdfiumTextEngine
    with _PdfiumTextInspection
    implements PdfTextEngine {
  const PdfiumTextEngine({this.fontCatalog});

  final InstalledFontCatalog? fontCatalog;

  @override
  Future<PdfNativeProjectionResult> projectTextBlock({
    required PdfDocument document,
    required PdfNativeProjectionRequest request,
  }) => const PdfiumWorkerExecutor().run(
    document: document,
    callback: _projectTextBlockOnWorker,
    message: request,
  );

  @override
  Future<Uint8List> encodeLiveDocument({required PdfDocument document}) =>
      document.encodePdf(incremental: false);

  static final Expando<String> _knownRevisions = Expando<String>();
  @override
  Future<Uint8List> applyDraft({
    required PdfDocument document,
    required PdfEditingSession draft,
  }) async {
    final transformedLocators = draft.commands
        .take(draft.cursor)
        .whereType<TransformPdfPageObjectCommand>()
        .map((command) => command.locator)
        .toSet();
    final formattedLocators = draft.commands
        .take(draft.cursor)
        .whereType<FormatPdfTextCommand>()
        .map((command) => command.locator)
        .toSet();
    final fontChangedLocators = draft.commands
        .take(draft.cursor)
        .whereType<FormatPdfTextCommand>()
        .where(
          (command) =>
              command.before.fontFamily != command.after.fontFamily ||
              command.before.fontWeight != command.after.fontWeight ||
              command.before.italic != command.after.italic,
        )
        .map((command) => command.locator)
        .toSet();
    final geometryLocators = draft.commands
        .take(draft.cursor)
        .where(
          (command) =>
              command is MovePdfTextBlockCommand ||
              command is ResizePdfTextBlockCommand,
        )
        .expand((command) => command.affectedLocators)
        .toSet();
    final resizeLocators = draft.commands
        .take(draft.cursor)
        .whereType<ResizePdfTextBlockCommand>()
        .map((command) => command.locator)
        .toSet();
    final changed = draft.blocks
        .where(
          (block) =>
              block.text != block.originalText ||
              formattedLocators.contains(block.locator) ||
              geometryLocators.contains(block.locator),
        )
        .toList(growable: false);
    if (changed.any((block) => !block.isEditable)) {
      final block = changed.firstWhere((block) => !block.isEditable);
      throw PdfReadOnlyTextBlockFailure(
        locator: block.locator,
        reason: block.readOnlyReason ?? PdfReadOnlyReason.complexRendering,
      );
    }
    final matchedFaces = <PdfTextBlockLocator, Map<int, InstalledFontFace>>{};
    if (fontChangedLocators.isNotEmpty) {
      final catalog = fontCatalog ?? await InstalledFontCatalog.scan();
      for (final block in changed.where(
        (block) => fontChangedLocators.contains(block.locator),
      )) {
        final byRun = <int, InstalledFontFace>{};
        for (final run in block.runs) {
          try {
            byRun[run.range.start] = catalog
                .match(
                  FontMatchRequest(
                    family: run.style.fontFamily,
                    weight: run.style.fontWeight,
                    italic: run.style.italic,
                    text: block.text.substring(run.range.start, run.range.end),
                  ),
                )
                .font;
          } on FontMatchUnavailable catch (error) {
            throw PdfFontUnavailableFailure(error.message);
          }
        }
        matchedFaces[block.locator] = byRun;
      }
    }
    await const PdfiumWorkerExecutor().run(
      document: document,
      callback: _applyDraftOnWorker,
      message: _ApplyDraftWorkerMessage(
        changed: changed,
        formattedLocators: formattedLocators,
        geometryLocators: geometryLocators,
        resizeLocators: resizeLocators,
        matchedFaces: matchedFaces,
        transformedLocators: transformedLocators,
        pageObjects: draft.pageObjects,
      ),
    );
    return document.encodePdf(incremental: false);
  }

  _NativeBlockReplacement _replaceFormattedBlock(
    FPDF_DOCUMENT document,
    FPDF_PAGE page,
    PdfTextBlock block,
    Map<int, InstalledFontFace>? matchedFaces, {
    required bool reflow,
  }) {
    final originals = block.objectPaths
        .map((path) => _objectAtPath(page, path))
        .toList(growable: false);
    if (originals.any(
      (object) =>
          object.address == 0 ||
          pdfiumBindings.FPDFPageObj_GetType(object) != FPDF_PAGEOBJ_TEXT,
    )) {
      throw PdfStaleLocatorFailure(block.locator);
    }
    final sourceFont = pdfiumBindings.FPDFTextObj_GetFont(originals.first);
    if (sourceFont.address == 0) {
      throw const PdfFontUnavailableFailure(
        'The source font cannot be reused for this edit.',
      );
    }
    final created = <FPDF_PAGEOBJECT>[];
    final loadedFonts = <FPDF_FONT>[];
    final segments = _segmentsFor(block, reflow: reflow, font: sourceFont);
    for (final segment in segments) {
      final run = segment.run;
      final face = matchedFaces?[run.range.start];
      final font = face == null
          ? sourceFont
          : _loadInstalledFont(document, face);
      if (face != null) loadedFonts.add(font);
      final object = pdfiumBindings.FPDFPageObj_CreateTextObj(
        document,
        font,
        run.style.fontSize,
      );
      if (object.address == 0) {
        throw const PdfFontUnavailableFailure(
          'Could not create a formatted PDF text object.',
        );
      }
      _setObjectText(object, segment.text);
      _setObjectStyleAndPosition(
        object,
        block,
        run,
        originX: segment.originX,
        baseline: segment.baseline,
      );
      created.add(object);
      if (run.style.underline) {
        created.add(_createUnderline(block, run));
      }
    }
    for (final object in originals.reversed) {
      if (pdfiumBindings.FPDFPage_RemoveObject(page, object) == 0) {
        throw PdfValidationFailure('Could not replace a PDF text object.');
      }
      pdfiumBindings.FPDFPageObj_Destroy(object);
    }
    for (final object in created) {
      if (pdfiumBindings.FPDFPage_InsertObject(page, object) == 0) {
        throw PdfValidationFailure('Could not insert formatted PDF text.');
      }
    }
    for (final font in loadedFonts) {
      pdfiumBindings.FPDFFont_Close(font);
    }
    return _NativeBlockReplacement(
      lineRanges: List<PdfTextRange>.unmodifiable(
        segments.map((segment) => segment.run.range),
      ),
      textObjectCount: segments.length,
    );
  }

  List<_NativeTextSegment> _segmentsFor(
    PdfTextBlock block, {
    required bool reflow,
    required FPDF_FONT font,
  }) {
    // Keep an invisible whitespace text object as the editable insertion
    // anchor. PDFium discards a truly empty object during content generation;
    // if the last object disappears, the next keystroke has no native target.
    if (block.text.isEmpty) {
      final style = block.runs.isEmpty
          ? throw const PdfFontUnavailableFailure(
              'The empty text block has no reusable font style.',
            )
          : block.runs.first.style;
      return <_NativeTextSegment>[
        _NativeTextSegment(
          text: ' ',
          run: PdfTextRun(range: const PdfTextRange(0, 0), style: style),
          originX: block.bounds.left,
          baseline: block.baseline,
        ),
      ];
    }
    if (reflow) {
      final width = calloc<Float>();
      final ascent = calloc<Float>();
      final descent = calloc<Float>();
      try {
        final layout = const PdfNativeTextLayoutEngine().layout(
          text: block.text,
          bounds: block.bounds,
          runs: block.runs,
          baseline: block.baseline,
          direction: block.writingDirection,
          advance: (codePoint, style) {
            final measured =
                pdfiumBindings.FPDFFont_GetGlyphWidth(
                  font,
                  codePoint,
                  style.fontSize,
                  width,
                ) !=
                0;
            return (measured ? width.value : style.fontSize * 0.5) +
                style.characterSpacing;
          },
          lineHeight: (style) {
            final hasAscent =
                pdfiumBindings.FPDFFont_GetAscent(
                  font,
                  style.fontSize,
                  ascent,
                ) !=
                0;
            final hasDescent =
                pdfiumBindings.FPDFFont_GetDescent(
                  font,
                  style.fontSize,
                  descent,
                ) !=
                0;
            final nativeHeight = hasAscent && hasDescent
                ? ascent.value - descent.value
                : style.fontSize;
            return nativeHeight + style.lineSpacing;
          },
        );
        return layout.lines
            .where((line) => line.text.isNotEmpty)
            .map(
              (line) => _NativeTextSegment(
                text: line.text,
                run: PdfTextRun(
                  range: line.range,
                  style: block.styleAt(line.range.start),
                ),
                originX: line.originX,
                baseline: line.baseline,
              ),
            )
            .toList(growable: false);
      } finally {
        calloc.free(width);
        calloc.free(ascent);
        calloc.free(descent);
      }
    }
    if (block.runs.length == 1) {
      return <_NativeTextSegment>[
        _NativeTextSegment(
          text: block.text,
          run: block.runs.single,
          originX: block.bounds.left,
          baseline: block.baseline,
        ),
      ];
    }
    return block.runs
        .where((run) => !run.range.isEmpty)
        .map(
          (run) => _NativeTextSegment(
            text: block.text.substring(run.range.start, run.range.end),
            run: run,
            originX:
                block.bounds.left +
                block.bounds.width * run.range.start / block.text.length,
            baseline: block.baseline,
          ),
        )
        .toList(growable: false);
  }

  FPDF_PAGEOBJECT _createUnderline(PdfTextBlock block, PdfTextRun run) {
    final length = block.text.isEmpty ? 1 : block.text.length;
    final start =
        block.bounds.left + block.bounds.width * run.range.start / length;
    final end = block.bounds.left + block.bounds.width * run.range.end / length;
    final y = block.baseline - run.style.fontSize * 0.12;
    final path = pdfiumBindings.FPDFPageObj_CreateNewPath(start, y);
    if (path.address == 0 ||
        pdfiumBindings.FPDFPath_LineTo(path, end, y) == 0) {
      throw PdfValidationFailure('Could not create PDF text underline.');
    }
    final color = run.style.fillColorValue;
    if (pdfiumBindings.FPDFPageObj_SetStrokeColor(
              path,
              (color >> 16) & 0xff,
              (color >> 8) & 0xff,
              color & 0xff,
              (color >> 24) & 0xff,
            ) ==
            0 ||
        pdfiumBindings.FPDFPageObj_SetStrokeWidth(
              path,
              (run.style.fontSize / 14).clamp(0.5, 1.5),
            ) ==
            0 ||
        pdfiumBindings.FPDFPath_SetDrawMode(path, 0, 1) == 0) {
      pdfiumBindings.FPDFPageObj_Destroy(path);
      throw PdfValidationFailure('Could not style PDF text underline.');
    }
    return path;
  }

  FPDF_FONT _loadInstalledFont(FPDF_DOCUMENT document, InstalledFontFace face) {
    if (!face.mayEmbed) {
      throw PdfFontUnavailableFailure(
        '${face.family} does not permit PDF embedding.',
      );
    }
    final bytes = File(face.path).readAsBytesSync();
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final font = pdfiumBindings.FPDFText_LoadFont(
        document,
        buffer,
        bytes.length,
        FPDF_FONT_TRUETYPE,
        1,
      );
      if (font.address == 0) {
        throw PdfFontUnavailableFailure(
          'Could not embed ${face.family} in the PDF.',
        );
      }
      return font;
    } finally {
      calloc.free(buffer);
    }
  }

  void _setObjectStyleAndPosition(
    FPDF_PAGEOBJECT object,
    PdfTextBlock block,
    PdfTextRun run, {
    double? originX,
    double? baseline,
  }) {
    final color = run.style.fillColorValue;
    final alpha = (color >> 24) & 0xff;
    final red = (color >> 16) & 0xff;
    final green = (color >> 8) & 0xff;
    final blue = color & 0xff;
    if (pdfiumBindings.FPDFPageObj_SetFillColor(
          object,
          red,
          green,
          blue,
          alpha,
        ) ==
        0) {
      throw PdfValidationFailure('Could not set PDF text color.');
    }
    final matrix = calloc<FS_MATRIX>();
    try {
      final progress = block.text.isEmpty
          ? 0.0
          : run.range.start / block.text.length;
      matrix.ref
        ..a = block.transform.a * run.style.horizontalScaling
        ..b = block.transform.b
        ..c = block.transform.c
        ..d = block.transform.d
        ..e =
            originX ??
            block.transform.translateX + block.bounds.width * progress
        ..f =
            (baseline ?? block.transform.translateY) +
            run.style.baselineShift * run.style.fontSize;
      if (pdfiumBindings.FPDFPageObj_SetMatrix(object, matrix) == 0) {
        throw PdfValidationFailure('Could not position formatted PDF text.');
      }
    } finally {
      calloc.free(matrix);
    }
  }

  @override
  Future<List<PdfTextBlock>> inspectPages({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) async {
    for (final pageNumber in pageNumbers) {
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        throw RangeError.range(
          pageNumber,
          1,
          document.pages.length,
          'pageNumber',
        );
      }
    }
    final blocks = await _inspect(
      document: document,
      sourceRevision: sourceRevision,
      pageNumbers: pageNumbers,
    );
    _knownRevisions[document] = sourceRevision;
    return blocks;
  }

  @override
  Future<PdfResolvedTextObject> resolveLocator({
    required PdfDocument document,
    required PdfTextBlockLocator locator,
  }) async {
    if (_knownRevisions[document] != locator.sourceRevision) {
      throw PdfStaleLocatorFailure(locator);
    }
    final blocks = await _inspect(
      document: document,
      sourceRevision: locator.sourceRevision,
      pageNumbers: <int>[locator.pageNumber],
    );
    final exact = blocks.where(
      (block) =>
          _samePath(block.locator.objectPath, locator.objectPath) &&
          _sameFingerprints(block.locator, locator),
    );
    if (exact.length == 1) {
      return PdfResolvedTextObject(block: exact.single);
    }
    final verified = blocks
        .where((block) => _sameFingerprints(block.locator, locator))
        .toList(growable: false);
    if (verified.isEmpty) throw PdfStaleLocatorFailure(locator);
    if (verified.length > 1) {
      throw PdfAmbiguousLocatorFailure(locator, verified.length);
    }
    return PdfResolvedTextObject(block: verified.single);
  }

  @override
  Future<List<PdfPageObject>> inspectPageObjects({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) async {
    for (final pageNumber in pageNumbers) {
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        throw RangeError.range(
          pageNumber,
          1,
          document.pages.length,
          'pageNumber',
        );
      }
    }
    final result = await const PdfiumWorkerExecutor().run(
      document: document,
      callback: _inspectPageObjectsOnWorker,
      message: (pageNumbers: pageNumbers, sourceRevision: sourceRevision),
    );
    _knownRevisions[document] = sourceRevision;
    return result;
  }

  @override
  Future<PdfPageObject> resolvePageObject({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
  }) async {
    if (_knownRevisions[document] != locator.sourceRevision) {
      throw PdfStalePageObjectLocatorFailure(locator);
    }
    final objects = await inspectPageObjects(
      document: document,
      sourceRevision: locator.sourceRevision,
      pageNumbers: <int>[locator.pageNumber],
    );
    for (final object in objects) {
      if (object.locator == locator) return object;
    }
    throw PdfStalePageObjectLocatorFailure(locator);
  }

  @override
  Future<void> setTextObjectsVisible({
    required PdfDocument document,
    required PdfTextBlock block,
    required bool visible,
  }) => const PdfiumWorkerExecutor().run(
    document: document,
    callback: _setTextObjectsVisibleOnWorker,
    message: (block: block, visible: visible),
  );

  @override
  Future<void> setPageObjectPreviewTransform({
    required PdfDocument document,
    required PdfPageObjectLocator locator,
    required PdfTransform transform,
  }) => const PdfiumWorkerExecutor().run(
    document: document,
    callback: _setPageObjectPreviewTransformOnWorker,
    message: (locator: locator, transform: transform),
  );

  void _visitPageObject({
    required FPDF_PAGEOBJECT object,
    required int pageNumber,
    required List<int> path,
    required String sourceRevision,
    required bool nested,
    required List<PdfPageObject> output,
  }) {
    if (object.address == 0) return;
    final nativeType = pdfiumBindings.FPDFPageObj_GetType(object);
    final type = _pageObjectType(nativeType);
    if (type == null) return;
    final left = calloc<Float>();
    final bottom = calloc<Float>();
    final right = calloc<Float>();
    final top = calloc<Float>();
    final matrix = calloc<FS_MATRIX>();
    try {
      final hasBounds =
          pdfiumBindings.FPDFPageObj_GetBounds(
            object,
            left,
            bottom,
            right,
            top,
          ) !=
          0;
      pdfiumBindings.FPDFPageObj_GetMatrix(object, matrix);
      final bounds = hasBounds
          ? PdfBox(left.value, bottom.value, right.value, top.value)
          : const PdfBox(0, 0, 0, 0);
      final transform = PdfTransform(
        matrix.ref.a,
        matrix.ref.b,
        matrix.ref.c,
        matrix.ref.d,
        matrix.ref.e,
        matrix.ref.f,
      );
      final geometryDigest = _digest(
        <Object>[
          _quantize(bounds.left),
          _quantize(bounds.bottom),
          _quantize(bounds.right),
          _quantize(bounds.top),
          _quantize(transform.a),
          _quantize(transform.b),
          _quantize(transform.c),
          _quantize(transform.d),
          _quantize(transform.translateX),
          _quantize(transform.translateY),
        ].join('|'),
      );
      final readOnlyReason = nested
          ? PdfPageObjectReadOnlyReason.sharedFormObject
          : (transform.determinant.abs() < 1e-12
                ? PdfPageObjectReadOnlyReason.singularTransform
                : null);
      final capabilities =
          readOnlyReason == null && type != PdfPageObjectType.form
          ? <PdfPageObjectCapability>{
              PdfPageObjectCapability.inspect,
              PdfPageObjectCapability.move,
              PdfPageObjectCapability.resize,
              PdfPageObjectCapability.rotate,
              if (type == PdfPageObjectType.text)
                PdfPageObjectCapability.editText,
            }
          : <PdfPageObjectCapability>{PdfPageObjectCapability.inspect};
      output.add(
        PdfPageObject(
          locator: PdfPageObjectLocator(
            pageNumber: pageNumber,
            objectPath: path,
            type: type,
            contentDigest: _digest('${type.name}:${path.join('.')}'),
            geometryDigest: geometryDigest,
            sourceRevision: sourceRevision,
          ),
          bounds: bounds,
          transform: transform,
          capabilities: capabilities,
          readOnlyReason:
              readOnlyReason ??
              (type == PdfPageObjectType.form
                  ? PdfPageObjectReadOnlyReason.sharedFormObject
                  : null),
        ),
      );
      if (type == PdfPageObjectType.form) {
        final count = pdfiumBindings.FPDFFormObj_CountObjects(object);
        for (var index = 0; index < count; index++) {
          _visitPageObject(
            object: pdfiumBindings.FPDFFormObj_GetObject(object, index),
            pageNumber: pageNumber,
            path: <int>[...path, index],
            sourceRevision: sourceRevision,
            nested: true,
            output: output,
          );
        }
      }
    } finally {
      calloc.free(left);
      calloc.free(bottom);
      calloc.free(right);
      calloc.free(top);
      calloc.free(matrix);
    }
  }

  Future<List<PdfTextBlock>> _inspect({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) => const PdfiumWorkerExecutor().run(
    document: document,
    callback: _inspectTextOnWorker,
    message: (pageNumbers: pageNumbers, sourceRevision: sourceRevision),
  );

  List<PdfTextBlock> _inspectPage(
    FPDF_DOCUMENT document,
    int pageNumber,
    String sourceRevision,
  ) {
    final bindings = pdfiumBindings;
    final page = bindings.FPDF_LoadPage(document, pageNumber - 1);
    if (page.address == 0) return const <PdfTextBlock>[];
    final textPage = bindings.FPDFText_LoadPage(page);
    if (textPage.address == 0) {
      bindings.FPDF_ClosePage(page);
      return const <PdfTextBlock>[];
    }
    try {
      final objects = <_DiscoveredObject>[];
      final count = bindings.FPDFPage_CountObjects(page);
      for (var index = 0; index < count; index++) {
        final object = bindings.FPDFPage_GetObject(page, index);
        _visitObject(
          object: object,
          textPage: textPage,
          path: <int>[index],
          insideForm: false,
          output: objects,
        );
      }
      final groups = const PdfTextBlockGrouper().group(
        objects.map((item) => item.snapshot).toList(growable: false),
      );
      return groups
          .map(
            (group) =>
                _blockFromGroup(group, objects, pageNumber, sourceRevision),
          )
          .toList(growable: false);
    } finally {
      bindings.FPDFText_ClosePage(textPage);
      bindings.FPDF_ClosePage(page);
    }
  }

  void _visitObject({
    required FPDF_PAGEOBJECT object,
    required FPDF_TEXTPAGE textPage,
    required List<int> path,
    required bool insideForm,
    required List<_DiscoveredObject> output,
  }) {
    if (object.address == 0) return;
    final bindings = pdfiumBindings;
    final type = bindings.FPDFPageObj_GetType(object);
    if (type == FPDF_PAGEOBJ_TEXT) {
      final snapshot = _readTextObject(object, textPage, path);
      if (snapshot != null) {
        output.add(
          _DiscoveredObject(
            snapshot: snapshot,
            readOnlyReason: insideForm
                ? PdfReadOnlyReason.sharedFormObject
                : _renderModeReadOnlyReason(
                    bindings.FPDFTextObj_GetTextRenderMode(object),
                  ),
          ),
        );
      }
      return;
    }
    if (type != FPDF_PAGEOBJ_FORM) return;
    final count = bindings.FPDFFormObj_CountObjects(object);
    for (var index = 0; index < count; index++) {
      _visitObject(
        object: bindings.FPDFFormObj_GetObject(object, index),
        textPage: textPage,
        path: <int>[...path, index],
        insideForm: true,
        output: output,
      );
    }
  }
}
