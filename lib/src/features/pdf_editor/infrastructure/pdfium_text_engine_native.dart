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
import 'pdf_text_block_grouper.dart';
import 'pdf_text_engine.dart';
import 'installed_font_catalog.dart';
import 'pdf_native_text_layout.dart';
import 'pdfium_worker_executor.dart';

PdfTextEngine createPdfTextEngine() => const PdfiumTextEngine();

final class PdfiumTextEngine implements PdfTextEngine {
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

  PdfTextObjectSnapshot? _readTextObject(
    FPDF_PAGEOBJECT object,
    FPDF_TEXTPAGE textPage,
    List<int> path,
  ) {
    final bindings = pdfiumBindings;
    final requiredLength = bindings.FPDFTextObj_GetText(
      object,
      textPage,
      nullptr.cast<FPDF_WCHAR>(),
      0,
    );
    if (requiredLength <= 1) return null;
    final byteBuffer = calloc<Uint8>(requiredLength);
    final buffer = byteBuffer.cast<FPDF_WCHAR>();
    final left = calloc<Float>();
    final bottom = calloc<Float>();
    final right = calloc<Float>();
    final top = calloc<Float>();
    final matrix = calloc<FS_MATRIX>();
    final fontSize = calloc<Float>();
    final red = calloc<UnsignedInt>();
    final green = calloc<UnsignedInt>();
    final blue = calloc<UnsignedInt>();
    final alpha = calloc<UnsignedInt>();
    try {
      final actualLength = bindings.FPDFTextObj_GetText(
        object,
        textPage,
        buffer,
        requiredLength,
      );
      if (actualLength <= 1 ||
          bindings.FPDFPageObj_GetBounds(object, left, bottom, right, top) ==
              0) {
        return null;
      }
      bindings.FPDFPageObj_GetMatrix(object, matrix);
      bindings.FPDFTextObj_GetFontSize(object, fontSize);
      bindings.FPDFPageObj_GetFillColor(object, red, green, blue, alpha);
      final font = bindings.FPDFTextObj_GetFont(object);
      final flags = font.address == 0 ? 0 : bindings.FPDFFont_GetFlags(font);
      final weight = font.address == 0
          ? 400
          : bindings.FPDFFont_GetWeight(font);
      final text = String.fromCharCodes(
        buffer.cast<Uint16>().asTypedList((actualLength ~/ 2) - 1),
      );
      final style = PdfTextStyle(
        fontFamily: _fontFamily(font),
        fontSize: fontSize.value,
        fillColorValue:
            (alpha.value << 24) |
            (red.value << 16) |
            (green.value << 8) |
            blue.value,
        fontWeight: weight <= 0 ? 400 : weight,
        italic: flags & 64 != 0,
        underline: false,
        baselineShift: 0,
        alignment: PdfTextAlignment.left,
        characterSpacing: 0,
        lineSpacing: 0,
        horizontalScaling: 1,
      );
      return PdfTextObjectSnapshot(
        objectPath: path,
        text: text,
        bounds: PdfBox(left.value, bottom.value, right.value, top.value),
        transform: PdfTransform(
          matrix.ref.a,
          matrix.ref.b,
          matrix.ref.c,
          matrix.ref.d,
          matrix.ref.e,
          matrix.ref.f,
        ),
        style: style,
        baseline: matrix.ref.f,
        writingDirection: PdfWritingDirection.leftToRight,
      );
    } finally {
      calloc.free(byteBuffer);
      calloc.free(left);
      calloc.free(bottom);
      calloc.free(right);
      calloc.free(top);
      calloc.free(matrix);
      calloc.free(fontSize);
      calloc.free(red);
      calloc.free(green);
      calloc.free(blue);
      calloc.free(alpha);
    }
  }

  String _fontFamily(FPDF_FONT font) {
    if (font.address == 0) return 'Unknown';
    final bindings = pdfiumBindings;
    final length = bindings.FPDFFont_GetFamilyName(
      font,
      nullptr.cast<Char>(),
      0,
    );
    if (length <= 1) return 'Unknown';
    final buffer = calloc<Char>(length);
    try {
      bindings.FPDFFont_GetFamilyName(font, buffer, length);
      return utf8.decode(
        buffer.cast<Uint8>().asTypedList(length - 1),
        allowMalformed: true,
      );
    } finally {
      calloc.free(buffer);
    }
  }

  PdfTextBlock _blockFromGroup(
    PdfTextObjectGroup group,
    List<_DiscoveredObject> discovered,
    int pageNumber,
    String sourceRevision,
  ) {
    final byPath = <String, _DiscoveredObject>{
      for (final item in discovered) item.snapshot.objectPath.join('.'): item,
    };
    final readOnlyReason = _firstReadOnlyReason(group.objectPaths, byPath);
    final runs = <PdfTextRun>[];
    var offset = 0;
    for (var index = 0; index < group.objects.length; index++) {
      final object = group.objects[index];
      final end = offset + object.text.length;
      if (end > offset) {
        runs.add(
          PdfTextRun(range: PdfTextRange(offset, end), style: object.style),
        );
      }
      offset = end;
      if (index < group.objects.length - 1) {
        final separator = _separatorBetween(object, group.objects[index + 1]);
        if (separator.isNotEmpty) {
          runs.add(
            PdfTextRun(
              range: PdfTextRange(offset, offset + separator.length),
              style: object.style,
            ),
          );
          offset += separator.length;
        }
      }
    }
    final text = _textForGroup(group);
    final locator = PdfTextBlockLocator(
      pageNumber: pageNumber,
      objectPath: group.objectPaths.first,
      textDigest: _digest(text),
      geometryDigest: _geometryDigest(group),
      fontFingerprint: _fontFingerprint(group),
      sourceRevision: sourceRevision,
    );
    return PdfTextBlock(
      locator: locator,
      text: text,
      originalText: text,
      runs: runs,
      bounds: group.bounds,
      transform: group.objects.first.transform,
      baseline: group.objects.first.baseline,
      writingDirection: group.objects.first.writingDirection,
      capabilities: readOnlyReason != null
          ? const <PdfTextCapability>[]
          : PdfTextCapability.values,
      readOnlyReason: readOnlyReason,
      objectPaths: group.objectPaths,
    );
  }
}

String _textForGroup(PdfTextObjectGroup group) {
  final buffer = StringBuffer();
  for (var index = 0; index < group.objects.length; index++) {
    if (index > 0) {
      final previous = group.objects[index - 1];
      final current = group.objects[index];
      buffer.write(_separatorBetween(previous, current));
    }
    buffer.write(group.objects[index].text);
  }
  return buffer.toString();
}

final class _ApplyDraftWorkerMessage {
  const _ApplyDraftWorkerMessage({
    required this.changed,
    required this.formattedLocators,
    required this.geometryLocators,
    required this.resizeLocators,
    required this.matchedFaces,
    required this.transformedLocators,
    required this.pageObjects,
  });

  final List<PdfTextBlock> changed;
  final Set<PdfTextBlockLocator> formattedLocators;
  final Set<PdfTextBlockLocator> geometryLocators;
  final Set<PdfTextBlockLocator> resizeLocators;
  final Map<PdfTextBlockLocator, Map<int, InstalledFontFace>> matchedFaces;
  final Set<PdfPageObjectLocator> transformedLocators;
  final List<PdfPageObject> pageObjects;
}

List<PdfPageObject> _inspectPageObjectsOnWorker(
  PdfiumWorkerInput<({List<int> pageNumbers, String sourceRevision})> input,
) {
  final nativeDocument = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final objects = <PdfPageObject>[];
  for (final pageNumber in input.message.pageNumbers) {
    final page = pdfiumBindings.FPDF_LoadPage(nativeDocument, pageNumber - 1);
    if (page.address == 0) continue;
    try {
      final count = pdfiumBindings.FPDFPage_CountObjects(page);
      for (var index = 0; index < count; index++) {
        const PdfiumTextEngine()._visitPageObject(
          object: pdfiumBindings.FPDFPage_GetObject(page, index),
          pageNumber: pageNumber,
          path: <int>[index],
          sourceRevision: input.message.sourceRevision,
          nested: false,
          output: objects,
        );
      }
    } finally {
      pdfiumBindings.FPDF_ClosePage(page);
    }
  }
  return List<PdfPageObject>.unmodifiable(objects);
}

List<PdfTextBlock> _inspectTextOnWorker(
  PdfiumWorkerInput<({List<int> pageNumbers, String sourceRevision})> input,
) {
  final nativeDocument = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final result = <PdfTextBlock>[];
  for (final pageNumber in input.message.pageNumbers) {
    result.addAll(
      const PdfiumTextEngine()._inspectPage(
        nativeDocument,
        pageNumber,
        input.message.sourceRevision,
      ),
    );
  }
  return List<PdfTextBlock>.unmodifiable(result);
}

PdfNativeProjectionResult _projectTextBlockOnWorker(
  PdfiumWorkerInput<PdfNativeProjectionRequest> input,
) {
  final request = input.message;
  final logicalBlock = request.block;
  final block = _retargetBlock(
    logicalBlock,
    request.nativeTarget ?? logicalBlock,
  );
  if (!block.isEditable) {
    throw PdfReadOnlyTextBlockFailure(
      locator: block.locator,
      reason: block.readOnlyReason ?? PdfReadOnlyReason.complexRendering,
    );
  }
  final nativeDocument = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  if (request.readOnlyGeometry) {
    final characters = _characterBoxesForText(
      nativeDocument,
      block.locator.pageNumber,
      block.text,
    );
    return PdfNativeProjectionResult(
      requestedRevision: request.editRevision,
      appliedRevision: request.editRevision,
      block: block,
      lines: <PdfNativeLine>[
        PdfNativeLine(
          range: PdfTextRange(0, block.text.length),
          bounds: block.bounds,
        ),
      ],
      characters: characters,
      affectedPages: <int>[block.locator.pageNumber],
    );
  }
  final page = pdfiumBindings.FPDF_LoadPage(
    nativeDocument,
    block.locator.pageNumber - 1,
  );
  if (page.address == 0) throw PdfStaleLocatorFailure(block.locator);
  late final _NativeBlockReplacement replacement;
  late final List<List<int>> createdObjectPaths;
  try {
    replacement = const PdfiumTextEngine()._replaceFormattedBlock(
      nativeDocument,
      page,
      block,
      null,
      reflow: true,
    );
    if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
      throw PdfValidationFailure(
        'Could not regenerate PDF page ${block.locator.pageNumber}.',
      );
    }
    final paths = <List<int>>[];
    final count = pdfiumBindings.FPDFPage_CountObjects(page);
    for (
      var index = count - 1;
      index >= 0 && paths.length < replacement.textObjectCount;
      index--
    ) {
      final object = pdfiumBindings.FPDFPage_GetObject(page, index);
      if (object.address != 0 &&
          pdfiumBindings.FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT) {
        paths.add(<int>[index]);
      }
    }
    if (paths.length != replacement.textObjectCount) {
      throw const PdfValidationFailure(
        'PDFium did not preserve every inserted text object.',
      );
    }
    createdObjectPaths = List<List<int>>.unmodifiable(paths.reversed);
  } finally {
    pdfiumBindings.FPDF_ClosePage(page);
  }

  final projected = _blockWithObjectPaths(block, createdObjectPaths);
  if (block.text.isEmpty) {
    return PdfNativeProjectionResult(
      requestedRevision: request.editRevision,
      appliedRevision: request.editRevision,
      block: projected,
      lines: const <PdfNativeLine>[],
      characters: const <PdfNativeCharacterBox>[],
      affectedPages: <int>[block.locator.pageNumber],
    );
  }

  final extractedCharacters = _characterBoxesForText(
    nativeDocument,
    block.locator.pageNumber,
    block.text,
  );
  final characters = extractedCharacters.isEmpty
      ? _fallbackCharacterBoxes(block)
      : extractedCharacters;
  return PdfNativeProjectionResult(
    requestedRevision: request.editRevision,
    appliedRevision: request.editRevision,
    block: projected,
    lines: _linesForRanges(replacement.lineRanges, characters),
    characters: characters,
    affectedPages: <int>[block.locator.pageNumber],
  );
}

List<PdfNativeCharacterBox> _fallbackCharacterBoxes(PdfTextBlock block) {
  if (block.text.isEmpty) return const <PdfNativeCharacterBox>[];
  final visibleOffsets = <int>[
    for (var offset = 0; offset < block.text.length; offset++)
      if (block.text[offset] != '\r' && block.text[offset] != '\n') offset,
  ];
  if (visibleOffsets.isEmpty) return const <PdfNativeCharacterBox>[];
  final width =
      (block.bounds.right - block.bounds.left) / visibleOffsets.length;
  return List<PdfNativeCharacterBox>.unmodifiable(<PdfNativeCharacterBox>[
    for (var index = 0; index < visibleOffsets.length; index++)
      PdfNativeCharacterBox(
        offset: visibleOffsets[index],
        bounds: PdfBox(
          block.bounds.left + (width * index),
          block.bounds.bottom,
          block.bounds.left + (width * (index + 1)),
          block.bounds.top,
        ),
      ),
  ]);
}

List<PdfNativeCharacterBox> _characterBoxesForText(
  FPDF_DOCUMENT document,
  int pageNumber,
  String text,
) {
  if (text.isEmpty) return const <PdfNativeCharacterBox>[];
  final page = pdfiumBindings.FPDF_LoadPage(document, pageNumber - 1);
  if (page.address == 0) return const <PdfNativeCharacterBox>[];
  final textPage = pdfiumBindings.FPDFText_LoadPage(page);
  if (textPage.address == 0) {
    pdfiumBindings.FPDF_ClosePage(page);
    return const <PdfNativeCharacterBox>[];
  }
  final left = calloc<Double>();
  final right = calloc<Double>();
  final bottom = calloc<Double>();
  final top = calloc<Double>();
  try {
    final pageText = StringBuffer();
    final characters = <_PageTextCharacter>[];
    final count = pdfiumBindings.FPDFText_CountChars(textPage);
    for (var index = 0; index < count; index++) {
      final value = String.fromCharCode(
        pdfiumBindings.FPDFText_GetUnicode(textPage, index),
      );
      if (value == '\r' || value == '\n') continue;
      final start = pageText.length;
      pageText.write(value);
      characters.add(
        _PageTextCharacter(
          nativeIndex: index,
          start: start,
          end: start + value.length,
        ),
      );
    }
    final searchableText = text.replaceAll('\r', '').replaceAll('\n', '');
    final matchStart = pageText.toString().indexOf(searchableText);
    if (matchStart == -1) return const <PdfNativeCharacterBox>[];
    final matchEnd = matchStart + searchableText.length;
    final result = <PdfNativeCharacterBox>[];
    for (final character in characters.where(
      (character) => character.start < matchEnd && character.end > matchStart,
    )) {
      if (pdfiumBindings.FPDFText_GetCharBox(
            textPage,
            character.nativeIndex,
            left,
            right,
            bottom,
            top,
          ) ==
          0) {
        continue;
      }
      final box = PdfBox(left.value, bottom.value, right.value, top.value);
      final firstOffset = character.start < matchStart
          ? 0
          : character.start - matchStart;
      final lastOffset = character.end > matchEnd
          ? searchableText.length
          : character.end - matchStart;
      for (var offset = firstOffset; offset < lastOffset; offset++) {
        result.add(PdfNativeCharacterBox(offset: offset, bounds: box));
      }
    }
    return List<PdfNativeCharacterBox>.unmodifiable(result);
  } finally {
    calloc.free(left);
    calloc.free(right);
    calloc.free(bottom);
    calloc.free(top);
    pdfiumBindings.FPDFText_ClosePage(textPage);
    pdfiumBindings.FPDF_ClosePage(page);
  }
}

List<PdfNativeLine> _linesForRanges(
  List<PdfTextRange> ranges,
  List<PdfNativeCharacterBox> characters,
) {
  if (ranges.isEmpty || characters.isEmpty) return const <PdfNativeLine>[];
  final lines = <PdfNativeLine>[];
  for (final range in ranges) {
    final boxes = characters
        .where(
          (character) =>
              range.start <= character.offset && character.offset < range.end,
        )
        .map((character) => character.bounds)
        .toList(growable: false);
    if (boxes.isEmpty) continue;
    lines.add(
      PdfNativeLine(
        range: range,
        bounds: PdfBox(
          boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b),
          boxes.map((box) => box.bottom).reduce((a, b) => a < b ? a : b),
          boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b),
          boxes.map((box) => box.top).reduce((a, b) => a > b ? a : b),
        ),
      ),
    );
  }
  return List<PdfNativeLine>.unmodifiable(lines);
}

final class _PageTextCharacter {
  const _PageTextCharacter({
    required this.nativeIndex,
    required this.start,
    required this.end,
  });

  final int nativeIndex;
  final int start;
  final int end;
}

final class _NativeBlockReplacement {
  const _NativeBlockReplacement({
    required this.lineRanges,
    required this.textObjectCount,
  });

  final List<PdfTextRange> lineRanges;
  final int textObjectCount;
}

PdfTextBlock _retargetBlock(PdfTextBlock desired, PdfTextBlock nativeTarget) =>
    PdfTextBlock(
      locator: nativeTarget.locator,
      text: desired.text,
      originalText: desired.originalText,
      runs: desired.runs,
      bounds: desired.bounds,
      transform: desired.transform,
      baseline: desired.baseline,
      writingDirection: desired.writingDirection,
      capabilities: desired.capabilities.toList(growable: false),
      readOnlyReason: desired.readOnlyReason,
      objectPaths: nativeTarget.objectPaths,
      overflow: desired.overflow,
    );

PdfTextBlock _blockWithObjectPaths(
  PdfTextBlock block,
  List<List<int>> objectPaths,
) => PdfTextBlock(
  locator: block.locator,
  text: block.text,
  originalText: block.originalText,
  runs: block.runs,
  bounds: block.bounds,
  transform: block.transform,
  baseline: block.baseline,
  writingDirection: block.writingDirection,
  capabilities: block.capabilities.toList(growable: false),
  readOnlyReason: block.readOnlyReason,
  objectPaths: objectPaths,
  overflow: block.overflow,
);

void _applyDraftOnWorker(PdfiumWorkerInput<_ApplyDraftWorkerMessage> input) {
  final message = input.message;
  final nativeDocument = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final byPage = <int, List<PdfTextBlock>>{};
  for (final block in message.changed) {
    byPage.putIfAbsent(block.locator.pageNumber, () => []).add(block);
  }
  for (final entry in byPage.entries) {
    final page = pdfiumBindings.FPDF_LoadPage(nativeDocument, entry.key - 1);
    if (page.address == 0) {
      throw PdfValidationFailure('Could not load PDF page ${entry.key}.');
    }
    try {
      for (final block in entry.value) {
        if (message.formattedLocators.contains(block.locator) ||
            message.geometryLocators.contains(block.locator)) {
          const PdfiumTextEngine()._replaceFormattedBlock(
            nativeDocument,
            page,
            block,
            message.matchedFaces[block.locator],
            reflow:
                message.formattedLocators.contains(block.locator) ||
                message.resizeLocators.contains(block.locator),
          );
        } else {
          for (var index = 0; index < block.objectPaths.length; index++) {
            final object = _objectAtPath(page, block.objectPaths[index]);
            if (object.address == 0 ||
                pdfiumBindings.FPDFPageObj_GetType(object) !=
                    FPDF_PAGEOBJ_TEXT) {
              throw PdfStaleLocatorFailure(block.locator);
            }
            _setObjectText(object, index == 0 ? block.text : '');
          }
        }
      }
      if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
        throw PdfValidationFailure(
          'Could not regenerate PDF page ${entry.key}.',
        );
      }
    } finally {
      pdfiumBindings.FPDF_ClosePage(page);
    }
  }

  final transformedByPage = <int, List<PdfPageObject>>{};
  for (final object in message.pageObjects.where(
    (object) => message.transformedLocators.contains(object.locator),
  )) {
    transformedByPage
        .putIfAbsent(object.locator.pageNumber, () => <PdfPageObject>[])
        .add(object);
  }
  for (final entry in transformedByPage.entries) {
    final page = pdfiumBindings.FPDF_LoadPage(nativeDocument, entry.key - 1);
    if (page.address == 0) {
      throw PdfValidationFailure('Could not load PDF page ${entry.key}.');
    }
    final matrix = calloc<FS_MATRIX>();
    try {
      for (final object in entry.value) {
        final nativeObject = _objectAtPath(page, object.locator.objectPath);
        if (nativeObject.address == 0 ||
            _pageObjectType(pdfiumBindings.FPDFPageObj_GetType(nativeObject)) !=
                object.locator.type) {
          throw PdfStalePageObjectLocatorFailure(object.locator);
        }
        matrix.ref
          ..a = object.transform.a
          ..b = object.transform.b
          ..c = object.transform.c
          ..d = object.transform.d
          ..e = object.transform.translateX
          ..f = object.transform.translateY;
        if (pdfiumBindings.FPDFPageObj_SetMatrix(nativeObject, matrix) == 0) {
          throw const PdfValidationFailure(
            'Could not persist a PDF object transform.',
          );
        }
      }
      if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
        throw PdfValidationFailure(
          'Could not regenerate PDF page ${entry.key}.',
        );
      }
    } finally {
      calloc.free(matrix);
      pdfiumBindings.FPDF_ClosePage(page);
    }
  }
}

final Map<int, Map<String, List<FPDF_TEXT_RENDERMODE>>>
_savedWorkerRenderModes = <int, Map<String, List<FPDF_TEXT_RENDERMODE>>>{};

void _setTextObjectsVisibleOnWorker(
  PdfiumWorkerInput<({PdfTextBlock block, bool visible})> input,
) {
  final block = input.message.block;
  final nativeDocument = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final page = pdfiumBindings.FPDF_LoadPage(
    nativeDocument,
    block.locator.pageNumber - 1,
  );
  if (page.address == 0) throw PdfStaleLocatorFailure(block.locator);
  try {
    final key = _textPreviewKey(block);
    final savedByBlock = _savedWorkerRenderModes.putIfAbsent(
      input.documentAddress,
      () => <String, List<FPDF_TEXT_RENDERMODE>>{},
    );
    if (!input.message.visible) {
      savedByBlock.putIfAbsent(
        key,
        () => block.objectPaths
            .map((path) {
              final object = _objectAtPath(page, path);
              if (object.address == 0 ||
                  pdfiumBindings.FPDFPageObj_GetType(object) !=
                      FPDF_PAGEOBJ_TEXT) {
                throw PdfStaleLocatorFailure(block.locator);
              }
              final mode = pdfiumBindings.FPDFTextObj_GetTextRenderMode(object);
              if (pdfiumBindings.FPDFTextObj_SetTextRenderMode(
                    object,
                    FPDF_TEXT_RENDERMODE.FPDF_TEXTRENDERMODE_INVISIBLE,
                  ) ==
                  0) {
                throw const PdfValidationFailure(
                  'PDFium could not suppress the native text preview.',
                );
              }
              return mode;
            })
            .toList(growable: false),
      );
    } else {
      final modes = savedByBlock.remove(key);
      if (modes != null) {
        for (var index = 0; index < block.objectPaths.length; index++) {
          final object = _objectAtPath(page, block.objectPaths[index]);
          if (object.address != 0) {
            pdfiumBindings.FPDFTextObj_SetTextRenderMode(object, modes[index]);
          }
        }
      }
      if (savedByBlock.isEmpty) {
        _savedWorkerRenderModes.remove(input.documentAddress);
      }
    }
    if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
      throw const PdfValidationFailure(
        'PDFium could not regenerate the edited preview page.',
      );
    }
  } finally {
    pdfiumBindings.FPDF_ClosePage(page);
  }
}

void _setPageObjectPreviewTransformOnWorker(
  PdfiumWorkerInput<({PdfPageObjectLocator locator, PdfTransform transform})>
  input,
) {
  final locator = input.message.locator;
  final transform = input.message.transform;
  if (!transform.isFinite || transform.determinant.abs() < 1e-12) {
    throw const PdfInvalidTransformFailure();
  }
  final nativeDocument = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final page = pdfiumBindings.FPDF_LoadPage(
    nativeDocument,
    locator.pageNumber - 1,
  );
  if (page.address == 0) throw PdfStalePageObjectLocatorFailure(locator);
  final matrix = calloc<FS_MATRIX>();
  try {
    final object = _objectAtPath(page, locator.objectPath);
    if (object.address == 0) throw PdfStalePageObjectLocatorFailure(locator);
    matrix.ref
      ..a = transform.a
      ..b = transform.b
      ..c = transform.c
      ..d = transform.d
      ..e = transform.translateX
      ..f = transform.translateY;
    if (pdfiumBindings.FPDFPageObj_SetMatrix(object, matrix) == 0 ||
        pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
      throw const PdfValidationFailure(
        'PDFium could not update the object preview transform.',
      );
    }
  } finally {
    calloc.free(matrix);
    pdfiumBindings.FPDF_ClosePage(page);
  }
}

String _separatorBetween(
  PdfTextObjectSnapshot previous,
  PdfTextObjectSnapshot current,
) {
  if (RegExp(r'\s$').hasMatch(previous.text) ||
      RegExp(r'^\s').hasMatch(current.text)) {
    return '';
  }
  final tolerance = (previous.style.fontSize + current.style.fontSize) * 0.25;
  return (previous.baseline - current.baseline).abs() <= tolerance ? ' ' : '\n';
}

final class _NativeTextSegment {
  const _NativeTextSegment({
    required this.text,
    required this.run,
    required this.originX,
    required this.baseline,
  });

  final String text;
  final PdfTextRun run;
  final double originX;
  final double baseline;
}

final class _DiscoveredObject {
  const _DiscoveredObject({
    required this.snapshot,
    required this.readOnlyReason,
  });

  final PdfTextObjectSnapshot snapshot;
  final PdfReadOnlyReason? readOnlyReason;
}

FPDF_PAGEOBJECT _objectAtPath(FPDF_PAGE page, List<int> path) {
  if (path.isEmpty) return nullptr.cast<fpdf_pageobject_t__>();
  var object = pdfiumBindings.FPDFPage_GetObject(page, path.first);
  for (var index = 1; index < path.length; index++) {
    if (object.address == 0 ||
        pdfiumBindings.FPDFPageObj_GetType(object) != FPDF_PAGEOBJ_FORM) {
      return nullptr.cast<fpdf_pageobject_t__>();
    }
    object = pdfiumBindings.FPDFFormObj_GetObject(object, path[index]);
  }
  return object;
}

void _setObjectText(FPDF_PAGEOBJECT object, String text) {
  final buffer = calloc<Uint16>(text.length + 1);
  try {
    final values = buffer.asTypedList(text.length + 1);
    values.setRange(0, text.length, text.codeUnits);
    values[text.length] = 0;
    if (pdfiumBindings.FPDFText_SetText(object, buffer.cast<FPDF_WCHAR>()) ==
        0) {
      throw const PdfValidationFailure(
        'PDFium could not encode replacement text with the current font.',
      );
    }
  } finally {
    calloc.free(buffer);
  }
}

PdfReadOnlyReason? _renderModeReadOnlyReason(FPDF_TEXT_RENDERMODE mode) =>
    mode == FPDF_TEXT_RENDERMODE.FPDF_TEXTRENDERMODE_FILL
    ? null
    : PdfReadOnlyReason.complexRendering;

PdfReadOnlyReason? _firstReadOnlyReason(
  List<List<int>> paths,
  Map<String, _DiscoveredObject> objects,
) {
  for (final path in paths) {
    final reason = objects[path.join('.')]!.readOnlyReason;
    if (reason != null) return reason;
  }
  return null;
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

String _textPreviewKey(PdfTextBlock block) =>
    '${block.locator.pageNumber}:${block.objectPaths.map((path) => path.join('.')).join(',')}';

PdfPageObjectType? _pageObjectType(int nativeType) => switch (nativeType) {
  FPDF_PAGEOBJ_TEXT => PdfPageObjectType.text,
  FPDF_PAGEOBJ_IMAGE => PdfPageObjectType.image,
  FPDF_PAGEOBJ_PATH => PdfPageObjectType.path,
  FPDF_PAGEOBJ_FORM => PdfPageObjectType.form,
  _ => null,
};

String _geometryDigest(PdfTextObjectGroup group) => _digest(
  group.objects
      .map(
        (object) => <Object>[
          ...object.objectPath,
          _quantize(object.bounds.left),
          _quantize(object.bounds.bottom),
          _quantize(object.bounds.right),
          _quantize(object.bounds.top),
          _quantize(object.transform.a),
          _quantize(object.transform.b),
          _quantize(object.transform.c),
          _quantize(object.transform.d),
          _quantize(object.transform.translateX),
          _quantize(object.transform.translateY),
        ].join(','),
      )
      .join('|'),
);

String _fontFingerprint(PdfTextObjectGroup group) => _digest(
  group.objects
      .map(
        (object) => <Object>[
          object.style.fontFamily,
          _quantize(object.style.fontSize),
          object.style.fontWeight,
          object.style.italic,
        ].join(','),
      )
      .join('|'),
);

int _quantize(double value) => (value * 1000).round();

bool _sameFingerprints(PdfTextBlockLocator left, PdfTextBlockLocator right) =>
    left.textDigest == right.textDigest &&
    left.geometryDigest == right.geometryDigest &&
    left.fontFingerprint == right.fontFingerprint;

bool _samePath(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
