part of 'pdfium_text_engine_native.dart';
mixin _PdfiumTextInspection {
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
