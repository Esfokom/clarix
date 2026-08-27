import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import '../../../core/editing/editor_bridge_types.dart';
import 'live_pdfium_tile_renderer.dart';
import 'pdfium_edit_plan_applier.dart';
import 'pdfium_worker_executor.dart';

/// Owns the live pdfrx/PDFium document used by editor tiles. Native PDFium
/// handles remain confined to the pdfrx worker; callers receive copied RGBA
/// bytes only.
final class LivePdfiumSession {
  LivePdfiumSession._(this._document) {
    _tiles = LivePdfiumTileRenderer(producer: _renderLiveTile);
  }

  final PdfDocument _document;
  late final LivePdfiumTileRenderer _tiles;
  bool _closed = false;
  int _revision = 0;

  static Future<LivePdfiumSession> open(String sourcePath) async =>
      LivePdfiumSession._(await PdfDocument.openFile(sourcePath));

  Future<EditorDirtyTile> renderTile(LivePdfiumTileRequest request) {
    _ensureOpen();
    return _tiles.render(request);
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
  Future<LivePdfiumApplyResult> apply(LivePdfiumEditPlan plan) async {
    _ensureOpen();
    final bounds = await const PdfiumWorkerExecutor().run(
      document: _document,
      callback: _applyTextPlanOnWorker,
      message: plan,
    );
    _revision += 1;
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

  Future<Uint8List> saveBytes() async {
    _ensureOpen();
    await commit();
    return _document.encodePdf();
  }

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

List<EditorPdfBox> _applyTextPlanOnWorker(
  PdfiumWorkerInput<LivePdfiumEditPlan> input,
) {
  final plan = input.message;
  final document = FPDF_DOCUMENT.fromAddress(input.documentAddress);
  final page = pdfiumBindings.FPDF_LoadPage(document, plan.pageNumber - 1);
  if (page.address == 0) throw StateError('PDFium could not load page');
  try {
    final resolved =
        <({FPDF_PAGEOBJECT object, String replacement, EditorPdfBox bounds})>[];
    for (final replacement in plan.replacements) {
      final locator = replacement.locator;
      if (locator.objectType != 'text' || locator.objectPath.length != 1) {
        throw ArgumentError(
          'live replacement currently requires one text object',
        );
      }
      final object = pdfiumBindings.FPDFPage_GetObject(
        page,
        locator.objectPath.single,
      );
      if (object.address == 0 ||
          pdfiumBindings.FPDFPageObj_GetType(object) != FPDF_PAGEOBJ_TEXT) {
        throw StateError('locator does not resolve to a text object');
      }
      final left = calloc<Float>();
      final bottom = calloc<Float>();
      final right = calloc<Float>();
      final top = calloc<Float>();
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
        resolved.add((
          object: object,
          replacement: replacement.replacement,
          bounds: EditorPdfBox(
            left: left.value,
            bottom: bottom.value,
            right: right.value,
            top: top.value,
          ),
        ));
      } finally {
        calloc.free(left);
        calloc.free(bottom);
        calloc.free(right);
        calloc.free(top);
      }
    }
    try {
      for (final replacement in resolved) {
        _setTextObjectText(replacement.object, replacement.replacement);
      }
      if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
        throw StateError('PDFium could not regenerate changed page content');
      }
      return resolved.map((item) => item.bounds).toList(growable: false);
    } catch (_) {
      // No page regeneration occurs until every object has been resolved and
      // changed, so resolution failures cannot leave a partial content stream.
      rethrow;
    }
  } finally {
    pdfiumBindings.FPDF_ClosePage(page);
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
