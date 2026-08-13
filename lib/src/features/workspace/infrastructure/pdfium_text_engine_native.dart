import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

import '../domain/pdf_text_types.dart';
import '../domain/pdf_edit_session.dart';
import 'pdf_text_block_grouper.dart';
import 'pdf_text_engine.dart';

PdfTextEngine createPdfTextEngine() => const PdfiumTextEngine();

final class PdfiumTextEngine implements PdfTextEngine {
  const PdfiumTextEngine();

  static final Expando<String> _knownRevisions = Expando<String>();

  @override
  Future<Uint8List> applyDraft({
    required PdfDocument document,
    required PdfEditingSession draft,
  }) async {
    final changed = draft.blocks
        .where((block) => block.text != block.originalText)
        .toList(growable: false);
    if (changed.any((block) => !block.isEditable)) {
      final block = changed.firstWhere((block) => !block.isEditable);
      throw PdfReadOnlyTextBlockFailure(
        locator: block.locator,
        reason: block.readOnlyReason ?? PdfReadOnlyReason.complexRendering,
      );
    }
    await document.useNativeDocumentHandle((address) {
      final nativeDocument = FPDF_DOCUMENT.fromAddress(address);
      final byPage = <int, List<PdfTextBlock>>{};
      for (final block in changed) {
        byPage.putIfAbsent(block.locator.pageNumber, () => []).add(block);
      }
      for (final entry in byPage.entries) {
        final page = pdfiumBindings.FPDF_LoadPage(
          nativeDocument,
          entry.key - 1,
        );
        if (page.address == 0) {
          throw PdfValidationFailure('Could not load PDF page ${entry.key}.');
        }
        try {
          for (final block in entry.value) {
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
          if (pdfiumBindings.FPDFPage_GenerateContent(page) == 0) {
            throw PdfValidationFailure(
              'Could not regenerate PDF page ${entry.key}.',
            );
          }
        } finally {
          pdfiumBindings.FPDF_ClosePage(page);
        }
      }
    });
    return document.encodePdf(incremental: false);
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

  Future<List<PdfTextBlock>> _inspect({
    required PdfDocument document,
    required String sourceRevision,
    required List<int> pageNumbers,
  }) => document.useNativeDocumentHandle((address) {
    final nativeDocument = FPDF_DOCUMENT.fromAddress(address);
    final result = <PdfTextBlock>[];
    for (final pageNumber in pageNumbers) {
      result.addAll(_inspectPage(nativeDocument, pageNumber, sourceRevision));
    }
    return List<PdfTextBlock>.unmodifiable(result);
  });

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
