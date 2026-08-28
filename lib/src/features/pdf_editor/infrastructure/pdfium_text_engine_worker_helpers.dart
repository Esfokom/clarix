part of 'pdfium_text_engine_native.dart';
String _textForGroup(PdfTextObjectGroup group) => joinObjectTexts(<
  PdfObjectTextSample
>[
  for (final object in group.objects)
    (
      text: object.text,
      fontSize: object.style.fontSize,
      baseline: object.baseline,
    ),
]);

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
) => separatorBetween(
  (
    text: previous.text,
    fontSize: previous.style.fontSize,
    baseline: previous.baseline,
  ),
  (
    text: current.text,
    fontSize: current.style.fontSize,
    baseline: current.baseline,
  ),
);

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
