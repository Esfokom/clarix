import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../domain/pdf_text_types.dart';
import 'live_pdfium_tile_renderer.dart';
import 'pdf_block_text.dart';
import 'pdfium_edit_plan_applier.dart';
import 'pdfium_page_object_path.dart';
import 'pdf_text_engine.dart';
import 'pdfium_worker_executor.dart';

abstract interface class LivePdfiumSessionOwner
    implements LivePdfiumPlanApplier {
  Future<void> close();
}

/// Synchronizes the physical PDFium document with the semantic revision.
abstract interface class LivePdfiumRevisionSync {
  int get appliedRevision;

  void seedRevision(int revision);

  void acknowledgeRevision(int revision);
}

/// Supplies one page scan from the PDFium document that owns live edits.
abstract interface class LivePdfiumPageImportSource {
  Future<LivePdfiumPageInspection> inspectPageForImport({
    required String sourceRevision,
    required int pageNumber,
  });
}

abstract interface class LivePdfiumSaveSource {
  Future<Uint8List> saveBytes();
}

final class LivePdfiumPageInspection {
  const LivePdfiumPageInspection({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.blocks,
  });

  final int pageNumber;
  final double width;
  final double height;
  final List<PdfTextBlock> blocks;
}

/// Owns the live pdfrx/PDFium document used by editor tiles. Native PDFium
/// handles remain confined to the pdfrx worker; callers receive copied RGBA
/// bytes only.
final class LivePdfiumSession
    implements
        LivePdfiumSessionOwner,
        LivePdfiumRevisionSync,
        LivePdfiumPageImportSource,
        LivePdfiumSaveSource {
  LivePdfiumSession._(this._document) {
    _tiles = LivePdfiumTileRenderer(producer: _renderLiveTile);
  }

  final PdfDocument _document;
  late final LivePdfiumTileRenderer _tiles;
  bool _closed = false;
  int _revision = 0;

  static Future<LivePdfiumSession> open(String sourcePath) async =>
      LivePdfiumSession._(await PdfDocument.openFile(sourcePath));

  @override
  int get appliedRevision => _revision;

  /// Aligns this session with Rust before any physical plan was applied.
  @override
  void seedRevision(int revision) {
    _ensureOpen();
    _revision = revision;
  }

  /// Aligns this session after a semantic-only publish.
  @override
  void acknowledgeRevision(int revision) {
    _ensureOpen();
    if (revision < _revision) {
      throw StateError(
        'cannot acknowledge a receding revision: $revision < $_revision',
      );
    }
    _revision = revision;
  }

  Future<EditorDirtyTile> renderTile(LivePdfiumTileRequest request) {
    _ensureOpen();
    return _tiles.render(request);
  }

  /// Inspects text through this session's document/worker, never through a
  /// second PDFium owner. This is the input boundary for the live importer.
  Future<List<PdfTextBlock>> inspectTextBlocks({
    required String sourceRevision,
    required List<int> pageNumbers,
  }) {
    _ensureOpen();
    return createPdfTextEngine().inspectPages(
      document: _document,
      sourceRevision: sourceRevision,
      pageNumbers: pageNumbers,
    );
  }

  @override
  Future<LivePdfiumPageInspection> inspectPageForImport({
    required String sourceRevision,
    required int pageNumber,
  }) async {
    _ensureOpen();
    final page = _document.pages[pageNumber - 1];
    final blocks = await inspectTextBlocks(
      sourceRevision: sourceRevision,
      pageNumbers: <int>[pageNumber],
    );
    return LivePdfiumPageInspection(
      pageNumber: pageNumber,
      width: page.width,
      height: page.height,
      blocks: List<PdfTextBlock>.unmodifiable(blocks),
    );
  }

  void invalidate({
    required int pageNumber,
    required EditorPdfBox bounds,
    required int revision,
  }) {
    _ensureOpen();
    _tiles.invalidate(
      pageNumber: pageNumber,
      bounds: bounds,
      revision: revision,
    );
  }

  Future<EditorTileInvalidation> replaceTextObject(
    EditorPhysicalLocator locator,
    String replacement,
  ) async => (await apply(
    LivePdfiumEditPlan(
      replacements: <LivePdfiumTextReplacement>[
        LivePdfiumTextReplacement(locator: locator, replacement: replacement),
      ],
    ),
  )).invalidations.single;

  /// Applies a same-page text transaction while its native page handle remains
  /// open. This is the safe batching primitive for live typing.
  @override
  Future<LivePdfiumApplyResult> apply(LivePdfiumEditPlan plan) async {
    _ensureOpen();
    final expectedRevision = plan.expectedRevision;
    if (expectedRevision != null && expectedRevision != _revision) {
      throw StateError(
        'live PDFium revision conflict: expected $expectedRevision, '
        'actual $_revision',
      );
    }
    final outcome = await const PdfiumWorkerExecutor().run(
      document: _document,
      callback: _applyTextPlanOnWorker,
      message: plan,
    );
    if (outcome.error case final String error) {
      throw StateError(error);
    }
    final bounds = outcome.bounds;
    _revision = plan.revision ?? _revision + 1;
    final invalidations = bounds
        .map((bounds) {
          _tiles.invalidate(
            pageNumber: plan.pageNumber,
            bounds: bounds,
            revision: _revision,
          );
          return EditorTileInvalidation(
            pageNumber: plan.pageNumber,
            bounds: bounds,
            revision: _revision,
          );
        })
        .toList(growable: false);
    return LivePdfiumApplyResult(
      revision: _revision,
      invalidations: invalidations,
    );
  }

  Future<Set<int>> commit() async {
    _ensureOpen();
    // Each single-object mutation regenerates before its FPDF_PAGE is closed.
    // A future same-page batch API will provide debounced regeneration safely.
    return const <int>{};
  }

  @override
  Future<Uint8List> saveBytes() async {
    _ensureOpen();
    await commit();
    return _document.encodePdf();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _tiles.clear();
    await _document.dispose();
  }

  Future<EditorDirtyTile> _renderLiveTile(LivePdfiumTileRequest request) =>
      const PdfiumWorkerExecutor().run(
        document: _document,
        callback: _renderPageTileOnWorker,
        message: request,
      );

  void _ensureOpen() {
    if (_closed) throw StateError('live PDFium session is closed');
  }
}

({List<EditorPdfBox> bounds, String? error}) _applyTextPlanOnWorker(
  PdfiumWorkerInput<LivePdfiumEditPlan> input,
) {
  try {
    return (bounds: _applyTextPlanOrThrow(input), error: null);
  } on Object catch (error) {
    return (bounds: const <EditorPdfBox>[], error: error.toString());
  }
}

List<EditorPdfBox> _applyTextPlanOrThrow(
  PdfiumWorkerInput<LivePdfiumEditPlan> input,
) {
  final plan = input.message;
  final document = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final page = pdfiumBindings.FPDF_LoadPage(document, plan.pageNumber - 1);
  if (page.address == 0) throw StateError('PDFium could not load page');
  final textPage = pdfiumBindings.FPDFText_LoadPage(page);
  if (textPage.address == 0) {
    pdfiumBindings.FPDF_ClosePage(page);
    throw StateError('PDFium could not load page text for transaction');
  }
  try {
    final resolved = <_ResolvedBlockReplacement>[];
    for (final replacement in plan.replacements) {
      final locator = replacement.locator;
      if (locator.objectType != 'text' || locator.allObjectPaths.isEmpty) {
        throw ArgumentError('live replacement requires a text locator');
      }
      final objects = <FPDF_PAGEOBJECT>[];
      final originalTexts = <String>[];
      final samples = <PdfObjectTextSample>[];
      var unionLeft = double.infinity;
      var unionBottom = double.infinity;
      var unionRight = double.negativeInfinity;
      var unionTop = double.negativeInfinity;
      for (final path in locator.allObjectPaths) {
        final object = objectAtPdfiumPath(page, path);
        if (object.address == 0 ||
            pdfiumBindings.FPDFPageObj_GetType(object) != FPDF_PAGEOBJ_TEXT) {
          throw StateError('locator does not resolve to a text object');
        }
        final metrics = _readTextObjectMetrics(object, textPage);
        objects.add(object);
        originalTexts.add(metrics.text);
        samples.add((
          text: metrics.text,
          fontSize: metrics.fontSize,
          baseline: metrics.baseline,
        ));
        unionLeft = math.min(unionLeft, metrics.bounds.left);
        unionBottom = math.min(unionBottom, metrics.bounds.bottom);
        unionRight = math.max(unionRight, metrics.bounds.right);
        unionTop = math.max(unionTop, metrics.bounds.top);
      }
      final expectedText = replacement.expectedText;
      if (expectedText != null &&
          expectedText.trimRight() != joinObjectTexts(samples).trimRight()) {
        throw StateError('locator text no longer matches the prepared plan');
      }
      final separators = <String>[
        for (var index = 0; index + 1 < samples.length; index++)
          separatorBetween(samples[index], samples[index + 1]),
      ];
      final segments = distributeReplacement(
        replacement: replacement.replacement,
        originalSegments: originalTexts,
        separators: separators,
      );
      resolved.add(
        _ResolvedBlockReplacement(
          objects: objects,
          originalTexts: originalTexts,
          segments: segments,
          bounds: EditorPdfBox(
            left: unionLeft,
            bottom: unionBottom,
            right: unionRight,
            top: unionTop,
          ),
        ),
      );
    }
    final changed = <({FPDF_PAGEOBJECT object, String originalText})>[];
    final changedTransforms =
        <({FPDF_PAGEOBJECT object, EditorAffineTransform original})>[];
    try {
      for (final replacement in resolved) {
        for (var index = 0; index < replacement.objects.length; index++) {
          _setTextObjectText(
            replacement.objects[index],
            replacement.segments[index],
          );
          changed.add((
            object: replacement.objects[index],
            originalText: replacement.originalTexts[index],
          ));
        }
      }
      for (final transform in plan.transforms) {
        if (transform.locator.objectType != 'text') {
          throw ArgumentError('live transform requires a text locator');
        }
        for (final path in transform.locator.allObjectPaths) {
          final object = objectAtPdfiumPath(page, path);
          if (object.address == 0 ||
              pdfiumBindings.FPDFPageObj_GetType(object) != FPDF_PAGEOBJ_TEXT) {
            throw StateError('locator does not resolve to a text object');
          }
          final original = _readObjectTransform(object);
          if (!_sameTransform(original, transform.expectedTransform)) {
            throw StateError(
              'locator transform no longer matches the prepared plan',
            );
          }
          _setObjectTransform(object, transform.transform);
          changedTransforms.add((object: object, original: original));
        }
      }
      if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
        throw StateError('PDFium could not regenerate changed page content');
      }
      return <EditorPdfBox>[
        ...resolved.map((replacement) => replacement.bounds),
        ...plan.transforms.expand(
          (transform) => <EditorPdfBox>[
            transform.oldBounds,
            transform.newBounds,
          ],
        ),
      ];
    } catch (_) {
      for (final original in changedTransforms.reversed) {
        _setObjectTransform(original.object, original.original);
      }
      for (final original in changed.reversed) {
        _setTextObjectText(original.object, original.originalText);
      }
      rethrow;
    }
  } finally {
    pdfiumBindings.FPDFText_ClosePage(textPage);
    pdfiumBindings.FPDF_ClosePage(page);
  }
}

final class _ResolvedBlockReplacement {
  _ResolvedBlockReplacement({
    required this.objects,
    required this.originalTexts,
    required this.segments,
    required this.bounds,
  });

  final List<FPDF_PAGEOBJECT> objects;
  final List<String> originalTexts;
  final List<String> segments;
  final EditorPdfBox bounds;
}

({String text, double fontSize, double baseline, EditorPdfBox bounds})
_readTextObjectMetrics(FPDF_PAGEOBJECT object, FPDF_TEXTPAGE textPage) {
  final left = calloc<Float>();
  final bottom = calloc<Float>();
  final right = calloc<Float>();
  final top = calloc<Float>();
  final fontSize = calloc<Float>();
  final matrix = calloc<FS_MATRIX>();
  try {
    if (pdfiumBindings.FPDFPageObj_GetBounds(
          object,
          left,
          bottom,
          right,
          top,
        ) ==
        0) {
      throw StateError('PDFium could not read text bounds');
    }
    final hasFontSize =
        pdfiumBindings.FPDFTextObj_GetFontSize(object, fontSize) != 0;
    pdfiumBindings.FPDFPageObj_GetMatrix(object, matrix);
    return (
      text: _readTextObjectText(object, textPage),
      fontSize: hasFontSize ? fontSize.value : 0,
      baseline: matrix.ref.f,
      bounds: EditorPdfBox(
        left: left.value,
        bottom: bottom.value,
        right: right.value,
        top: top.value,
      ),
    );
  } finally {
    calloc.free(left);
    calloc.free(bottom);
    calloc.free(right);
    calloc.free(top);
    calloc.free(fontSize);
    calloc.free(matrix);
  }
}

String _readTextObjectText(FPDF_PAGEOBJECT object, FPDF_TEXTPAGE textPage) {
  final length = pdfiumBindings.FPDFTextObj_GetText(
    object,
    textPage,
    nullptr.cast<FPDF_WCHAR>(),
    0,
  );
  if (length <= 1) return '';
  final buffer = calloc<Uint16>(length ~/ 2);
  try {
    final actual = pdfiumBindings.FPDFTextObj_GetText(
      object,
      textPage,
      buffer.cast<FPDF_WCHAR>(),
      length,
    );
    if (actual <= 1) throw StateError('PDFium could not read original text');
    return String.fromCharCodes(buffer.asTypedList((actual ~/ 2) - 1));
  } finally {
    calloc.free(buffer);
  }
}

void _setTextObjectText(FPDF_PAGEOBJECT object, String replacement) {
  final buffer = calloc<Uint16>(replacement.length + 1);
  try {
    final units = buffer.asTypedList(replacement.length + 1);
    units.setRange(0, replacement.length, replacement.codeUnits);
    units[replacement.length] = 0;
    if (pdfiumBindings.FPDFText_SetText(object, buffer.cast<FPDF_WCHAR>()) ==
        0) {
      throw StateError('PDFium could not encode replacement text');
    }
  } finally {
    calloc.free(buffer);
  }
}

EditorAffineTransform _readObjectTransform(FPDF_PAGEOBJECT object) {
  final matrix = calloc<FS_MATRIX>();
  try {
    if (pdfiumBindings.FPDFPageObj_GetMatrix(object, matrix) == 0) {
      throw StateError('PDFium could not read object transform');
    }
    return EditorAffineTransform(
      a: matrix.ref.a,
      b: matrix.ref.b,
      c: matrix.ref.c,
      d: matrix.ref.d,
      e: matrix.ref.e,
      f: matrix.ref.f,
    );
  } finally {
    calloc.free(matrix);
  }
}

void _setObjectTransform(FPDF_PAGEOBJECT object, EditorAffineTransform value) {
  final matrix = calloc<FS_MATRIX>();
  try {
    matrix.ref
      ..a = value.a
      ..b = value.b
      ..c = value.c
      ..d = value.d
      ..e = value.e
      ..f = value.f;
    if (pdfiumBindings.FPDFPageObj_SetMatrix(object, matrix) == 0) {
      throw StateError('PDFium could not update object transform');
    }
  } finally {
    calloc.free(matrix);
  }
}

bool _sameTransform(EditorAffineTransform left, EditorAffineTransform right) =>
    (left.a - right.a).abs() <= 1e-6 &&
    (left.b - right.b).abs() <= 1e-6 &&
    (left.c - right.c).abs() <= 1e-6 &&
    (left.d - right.d).abs() <= 1e-6 &&
    (left.e - right.e).abs() <= 1e-6 &&
    (left.f - right.f).abs() <= 1e-6;

EditorDirtyTile _renderPageTileOnWorker(
  PdfiumWorkerInput<LivePdfiumTileRequest> input,
) {
  final request = input.message;
  final document = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final page = pdfiumBindings.FPDF_LoadPage(document, request.pageNumber - 1);
  if (page.address == 0) {
    throw StateError('PDFium could not load page ${request.pageNumber}');
  }
  final bitmap = pdfiumBindings.FPDFBitmap_Create(
    request.width,
    request.height,
    0,
  );
  if (bitmap.address == 0) {
    pdfiumBindings.FPDF_ClosePage(page);
    throw StateError('PDFium could not allocate a live tile bitmap');
  }
  final matrix = calloc<FS_MATRIX>();
  final clip = calloc<FS_RECTF>();
  try {
    if (pdfiumBindings.FPDFBitmap_FillRect(
          bitmap,
          0,
          0,
          request.width,
          request.height,
          0xffffffff,
        ) ==
        0) {
      throw StateError('PDFium could not initialize a live tile bitmap');
    }
    final scaleX = request.width / (request.bounds.right - request.bounds.left);
    final scaleY =
        request.height / (request.bounds.top - request.bounds.bottom);
    matrix.ref
      ..a = scaleX
      ..b = 0
      ..c = 0
      ..d = -scaleY
      ..e = -request.bounds.left * scaleX
      ..f = request.bounds.top * scaleY;
    clip.ref
      ..left = 0
      ..top = 0
      ..right = request.width.toDouble()
      ..bottom = request.height.toDouble();
    pdfiumBindings.FPDF_RenderPageBitmapWithMatrix(
      bitmap,
      page,
      matrix,
      clip,
      0,
    );
    final stride = pdfiumBindings.FPDFBitmap_GetStride(bitmap);
    final source = pdfiumBindings.FPDFBitmap_GetBuffer(bitmap);
    if (source.address == 0 || stride < request.width * 4) {
      throw StateError('PDFium returned an invalid live tile bitmap');
    }
    final sourceBytes = source.cast<Uint8>().asTypedList(
      stride * request.height,
    );
    final rgba = Uint8List(request.width * request.height * 4);
    for (var y = 0; y < request.height; y++) {
      final sourceRow = y * stride;
      final targetRow = y * request.width * 4;
      for (var x = 0; x < request.width; x++) {
        final sourceIndex = sourceRow + x * 4;
        final targetIndex = targetRow + x * 4;
        rgba[targetIndex] = sourceBytes[sourceIndex + 2];
        rgba[targetIndex + 1] = sourceBytes[sourceIndex + 1];
        rgba[targetIndex + 2] = sourceBytes[sourceIndex];
        rgba[targetIndex + 3] = 255;
      }
    }
    return EditorDirtyTile(
      pageNumber: request.pageNumber,
      revision: request.revision,
      bounds: request.bounds,
      width: request.width,
      height: request.height,
      rgbaBytes: rgba,
    );
  } finally {
    calloc.free(matrix);
    calloc.free(clip);
    pdfiumBindings.FPDFBitmap_Destroy(bitmap);
    pdfiumBindings.FPDF_ClosePage(page);
  }
}
