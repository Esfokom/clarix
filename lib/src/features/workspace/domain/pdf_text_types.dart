enum PdfEditingMode { reading, text }

enum PdfCommandProvenance { manual, agent }

enum PdfTextAlignment { left, center, right, justify }

enum PdfTextCapability { replace, format, move, resize }

enum PdfWritingDirection { leftToRight, rightToLeft, vertical }

enum PdfReadOnlyReason {
  imageOnly,
  type3Font,
  vectorOutline,
  sharedFormObject,
  complexRendering,
  encrypted,
}

final class PdfTextRange {
  const PdfTextRange(this.start, this.end);

  final int start;
  final int end;

  bool get isEmpty => start == end;
  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is PdfTextRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

final class PdfBox {
  const PdfBox(this.left, this.bottom, this.right, this.top);

  final double left;
  final double bottom;
  final double right;
  final double top;

  double get width => right - left;
  double get height => top - bottom;

  @override
  bool operator ==(Object other) =>
      other is PdfBox &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, bottom, right, top);
}

final class PdfTransform {
  const PdfTransform(
    this.a,
    this.b,
    this.c,
    this.d,
    this.translateX,
    this.translateY,
  );

  final double a;
  final double b;
  final double c;
  final double d;
  final double translateX;
  final double translateY;

  @override
  bool operator ==(Object other) =>
      other is PdfTransform &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.translateX == translateX &&
      other.translateY == translateY;

  @override
  int get hashCode => Object.hash(a, b, c, d, translateX, translateY);
}

final class PdfTextBlockLocator {
  PdfTextBlockLocator({
    required this.pageNumber,
    required List<int> objectPath,
    required this.textDigest,
    required this.geometryDigest,
    required this.fontFingerprint,
    required this.sourceRevision,
  }) : objectPath = List<int>.unmodifiable(objectPath);

  final int pageNumber;
  final List<int> objectPath;
  final String textDigest;
  final String geometryDigest;
  final String fontFingerprint;
  final String sourceRevision;

  @override
  bool operator ==(Object other) =>
      other is PdfTextBlockLocator &&
      other.pageNumber == pageNumber &&
      _sameList(other.objectPath, objectPath) &&
      other.textDigest == textDigest &&
      other.geometryDigest == geometryDigest &&
      other.fontFingerprint == fontFingerprint &&
      other.sourceRevision == sourceRevision;

  @override
  int get hashCode => Object.hash(
    pageNumber,
    Object.hashAll(objectPath),
    textDigest,
    geometryDigest,
    fontFingerprint,
    sourceRevision,
  );
}

final class PdfTextObjectSnapshot {
  PdfTextObjectSnapshot({
    required List<int> objectPath,
    required this.text,
    required this.bounds,
    required this.transform,
    required this.style,
    required this.baseline,
    required this.writingDirection,
  }) : objectPath = List<int>.unmodifiable(objectPath);

  final List<int> objectPath;
  final String text;
  final PdfBox bounds;
  final PdfTransform transform;
  final PdfTextStyle style;
  final double baseline;
  final PdfWritingDirection writingDirection;

  @override
  bool operator ==(Object other) =>
      other is PdfTextObjectSnapshot &&
      _sameList(other.objectPath, objectPath) &&
      other.text == text &&
      other.bounds == bounds &&
      other.transform == transform &&
      other.style == style &&
      other.baseline == baseline &&
      other.writingDirection == writingDirection;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(objectPath),
    text,
    bounds,
    transform,
    style,
    baseline,
    writingDirection,
  );
}

final class PdfTextStyle {
  const PdfTextStyle({
    required this.fontFamily,
    required this.fontSize,
    required this.fillColorValue,
    required this.fontWeight,
    required this.italic,
    required this.underline,
    required this.baselineShift,
    required this.alignment,
    required this.characterSpacing,
    required this.lineSpacing,
    required this.horizontalScaling,
  });

  final String fontFamily;
  final double fontSize;
  final int fillColorValue;
  final int fontWeight;
  final bool italic;
  final bool underline;
  final double baselineShift;
  final PdfTextAlignment alignment;
  final double characterSpacing;
  final double lineSpacing;
  final double horizontalScaling;

  PdfTextStyle copyWith({
    String? fontFamily,
    double? fontSize,
    int? fillColorValue,
    int? fontWeight,
    bool? italic,
    bool? underline,
    double? baselineShift,
    PdfTextAlignment? alignment,
    double? characterSpacing,
    double? lineSpacing,
    double? horizontalScaling,
  }) => PdfTextStyle(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    fillColorValue: fillColorValue ?? this.fillColorValue,
    fontWeight: fontWeight ?? this.fontWeight,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    baselineShift: baselineShift ?? this.baselineShift,
    alignment: alignment ?? this.alignment,
    characterSpacing: characterSpacing ?? this.characterSpacing,
    lineSpacing: lineSpacing ?? this.lineSpacing,
    horizontalScaling: horizontalScaling ?? this.horizontalScaling,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfTextStyle &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fillColorValue == fillColorValue &&
      other.fontWeight == fontWeight &&
      other.italic == italic &&
      other.underline == underline &&
      other.baselineShift == baselineShift &&
      other.alignment == alignment &&
      other.characterSpacing == characterSpacing &&
      other.lineSpacing == lineSpacing &&
      other.horizontalScaling == horizontalScaling;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontSize,
    fillColorValue,
    fontWeight,
    italic,
    underline,
    baselineShift,
    alignment,
    characterSpacing,
    lineSpacing,
    horizontalScaling,
  );
}

final class PdfTextStylePatch {
  const PdfTextStylePatch({
    this.fontFamily,
    this.fontSize,
    this.fillColorValue,
    this.fontWeight,
    this.italic,
    this.underline,
    this.baselineShift,
    this.alignment,
    this.characterSpacing,
    this.lineSpacing,
    this.horizontalScaling,
  });

  final String? fontFamily;
  final double? fontSize;
  final int? fillColorValue;
  final int? fontWeight;
  final bool? italic;
  final bool? underline;
  final double? baselineShift;
  final PdfTextAlignment? alignment;
  final double? characterSpacing;
  final double? lineSpacing;
  final double? horizontalScaling;

  PdfTextStyle applyTo(PdfTextStyle style) => style.copyWith(
    fontFamily: fontFamily,
    fontSize: fontSize,
    fillColorValue: fillColorValue,
    fontWeight: fontWeight,
    italic: italic,
    underline: underline,
    baselineShift: baselineShift,
    alignment: alignment,
    characterSpacing: characterSpacing,
    lineSpacing: lineSpacing,
    horizontalScaling: horizontalScaling,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfTextStylePatch &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fillColorValue == fillColorValue &&
      other.fontWeight == fontWeight &&
      other.italic == italic &&
      other.underline == underline &&
      other.baselineShift == baselineShift &&
      other.alignment == alignment &&
      other.characterSpacing == characterSpacing &&
      other.lineSpacing == lineSpacing &&
      other.horizontalScaling == horizontalScaling;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    fontSize,
    fillColorValue,
    fontWeight,
    italic,
    underline,
    baselineShift,
    alignment,
    characterSpacing,
    lineSpacing,
    horizontalScaling,
  );
}

final class PdfTextRun {
  const PdfTextRun({required this.range, required this.style});

  final PdfTextRange range;
  final PdfTextStyle style;

  @override
  bool operator ==(Object other) =>
      other is PdfTextRun && other.range == range && other.style == style;

  @override
  int get hashCode => Object.hash(range, style);
}

final class PdfTextBlock {
  PdfTextBlock({
    required this.locator,
    required this.text,
    required this.originalText,
    required List<PdfTextRun> runs,
    required this.bounds,
    required this.transform,
    required this.baseline,
    required this.writingDirection,
    required List<PdfTextCapability> capabilities,
    required this.readOnlyReason,
    this.overflow = false,
  }) : runs = List<PdfTextRun>.unmodifiable(runs),
       capabilities = Set<PdfTextCapability>.unmodifiable(capabilities);

  final PdfTextBlockLocator locator;
  final String text;
  final String originalText;
  final List<PdfTextRun> runs;
  final PdfBox bounds;
  final PdfTransform transform;
  final double baseline;
  final PdfWritingDirection writingDirection;
  final Set<PdfTextCapability> capabilities;
  final PdfReadOnlyReason? readOnlyReason;
  final bool overflow;

  bool get isEditable =>
      readOnlyReason == null &&
      capabilities.contains(PdfTextCapability.replace);

  PdfTextStyle styleAt(int offset) {
    if (runs.isEmpty) {
      throw StateError(
        'A text block needs a style run before it can be edited.',
      );
    }
    if (offset == text.length) return runs.last.style;
    final int probe = offset;
    return runs
        .firstWhere(
          (PdfTextRun run) => run.range.start <= probe && probe < run.range.end,
        )
        .style;
  }

  PdfTextBlock replaceText(
    PdfTextRange range,
    String expected,
    String replacement,
  ) {
    _requireCapability(PdfTextCapability.replace);
    _requireRange(range);
    if (text.substring(range.start, range.end) != expected) {
      throw PdfTextMismatchFailure(locator: locator, expected: expected);
    }
    final String nextText =
        '${text.substring(0, range.start)}$replacement${text.substring(range.end)}';
    final PdfTextStyle replacementStyle = styleAt(range.start);
    return copyWith(
      text: nextText,
      runs: _replaceRuns(range, replacement.length, replacementStyle),
    );
  }

  PdfTextBlock formatRange(PdfTextRange range, PdfTextStyle style) {
    _requireCapability(PdfTextCapability.format);
    _requireRange(range);
    return copyWith(runs: _mapRunSegments(range, (PdfTextStyle _) => style));
  }

  PdfTextBlock withBoundsFor(PdfTextCapability capability, PdfBox bounds) {
    _requireCapability(capability);
    return copyWith(bounds: bounds);
  }

  void validateOperation(PdfTextCapability capability) =>
      _requireCapability(capability);

  PdfTextBlock copyWith({
    String? text,
    List<PdfTextRun>? runs,
    PdfBox? bounds,
    PdfTransform? transform,
    double? baseline,
    bool? overflow,
  }) => PdfTextBlock(
    locator: locator,
    text: text ?? this.text,
    originalText: originalText,
    runs: runs ?? this.runs,
    bounds: bounds ?? this.bounds,
    transform: transform ?? this.transform,
    baseline: baseline ?? this.baseline,
    writingDirection: writingDirection,
    capabilities: capabilities.toList(growable: false),
    readOnlyReason: readOnlyReason,
    overflow: overflow ?? this.overflow,
  );

  List<PdfTextRun> _replaceRuns(
    PdfTextRange range,
    int replacementLength,
    PdfTextStyle replacementStyle,
  ) {
    final int delta = replacementLength - range.length;
    final List<PdfTextRun> result = <PdfTextRun>[];
    for (final PdfTextRun run in runs) {
      if (run.range.start < range.start) {
        result.add(
          PdfTextRun(
            range: PdfTextRange(
              run.range.start,
              _min(run.range.end, range.start),
            ),
            style: run.style,
          ),
        );
      }
      if (run.range.end > range.end) {
        result.add(
          PdfTextRun(
            range: PdfTextRange(
              _max(run.range.start, range.end) + delta,
              run.range.end + delta,
            ),
            style: run.style,
          ),
        );
      }
    }
    if (replacementLength > 0) {
      result.add(
        PdfTextRun(
          range: PdfTextRange(range.start, range.start + replacementLength),
          style: replacementStyle,
        ),
      );
    }
    result.sort(
      (PdfTextRun left, PdfTextRun right) =>
          left.range.start.compareTo(right.range.start),
    );
    return _mergeAdjacentRuns(result);
  }

  List<PdfTextRun> _mapRunSegments(
    PdfTextRange range,
    PdfTextStyle Function(PdfTextStyle style) mapper,
  ) {
    final List<PdfTextRun> result = <PdfTextRun>[];
    for (final PdfTextRun run in runs) {
      final int start = run.range.start;
      final int end = run.range.end;
      if (start < range.start) {
        result.add(
          PdfTextRun(
            range: PdfTextRange(start, _min(end, range.start)),
            style: run.style,
          ),
        );
      }
      final int affectedStart = _max(start, range.start);
      final int affectedEnd = _min(end, range.end);
      if (affectedStart < affectedEnd) {
        result.add(
          PdfTextRun(
            range: PdfTextRange(affectedStart, affectedEnd),
            style: mapper(run.style),
          ),
        );
      }
      if (end > range.end) {
        result.add(
          PdfTextRun(
            range: PdfTextRange(_max(start, range.end), end),
            style: run.style,
          ),
        );
      }
    }
    return _mergeAdjacentRuns(result);
  }

  void _requireRange(PdfTextRange range) {
    if (range.start < 0 || range.end < range.start || range.end > text.length) {
      throw PdfInvalidTextRangeFailure(range: range, textLength: text.length);
    }
    if (_splitsSurrogatePair(range.start) || _splitsSurrogatePair(range.end)) {
      throw PdfInvalidTextRangeFailure(range: range, textLength: text.length);
    }
  }

  void _requireCapability(PdfTextCapability capability) {
    final PdfReadOnlyReason? reason = readOnlyReason;
    if (reason != null) {
      throw PdfReadOnlyTextBlockFailure(locator: locator, reason: reason);
    }
    if (!capabilities.contains(capability)) {
      throw PdfUnsupportedTextOperationFailure(
        locator: locator,
        capability: capability,
      );
    }
  }

  bool _splitsSurrogatePair(int offset) {
    if (offset == 0 || offset == text.length) return false;
    final int previous = text.codeUnitAt(offset - 1);
    final int next = text.codeUnitAt(offset);
    return previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
  }

  @override
  bool operator ==(Object other) =>
      other is PdfTextBlock &&
      other.locator == locator &&
      other.text == text &&
      other.originalText == originalText &&
      _sameList(other.runs, runs) &&
      other.bounds == bounds &&
      other.transform == transform &&
      other.baseline == baseline &&
      other.writingDirection == writingDirection &&
      _sameSet(other.capabilities, capabilities) &&
      other.readOnlyReason == readOnlyReason &&
      other.overflow == overflow;

  @override
  int get hashCode => Object.hash(
    locator,
    text,
    originalText,
    Object.hashAll(runs),
    bounds,
    transform,
    baseline,
    writingDirection,
    Object.hashAllUnordered(capabilities),
    readOnlyReason,
    overflow,
  );
}

final class PdfTextSelection {
  const PdfTextSelection({required this.locator, required this.range});

  final PdfTextBlockLocator locator;
  final PdfTextRange range;

  PdfTextRange rangeOrWholeBlock(int textLength) =>
      range.isEmpty ? PdfTextRange(0, textLength) : range;

  @override
  bool operator ==(Object other) =>
      other is PdfTextSelection &&
      other.locator == locator &&
      other.range == range;

  @override
  int get hashCode => Object.hash(locator, range);
}

final class PdfBookmarkSnapshot {
  const PdfBookmarkSnapshot({
    required this.id,
    required this.label,
    required this.pageNumber,
    required this.createdAt,
  });

  final String id;
  final String label;
  final int pageNumber;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is PdfBookmarkSnapshot &&
      other.id == id &&
      other.label == label &&
      other.pageNumber == pageNumber &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, label, pageNumber, createdAt);
}

final class PdfHighlightSnapshot {
  PdfHighlightSnapshot({
    required this.id,
    required this.pageNumber,
    required List<PdfBox> bounds,
    required this.selectedText,
    required this.note,
    required this.colorValue,
    required this.createdAt,
    required this.modifiedAt,
  }) : bounds = List<PdfBox>.unmodifiable(bounds);

  final String id;
  final int pageNumber;
  final List<PdfBox> bounds;
  final String selectedText;
  final String? note;
  final int colorValue;
  final DateTime createdAt;
  final DateTime modifiedAt;

  @override
  bool operator ==(Object other) =>
      other is PdfHighlightSnapshot &&
      other.id == id &&
      other.pageNumber == pageNumber &&
      _sameList(other.bounds, bounds) &&
      other.selectedText == selectedText &&
      other.note == note &&
      other.colorValue == colorValue &&
      other.createdAt == createdAt &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode => Object.hash(
    id,
    pageNumber,
    Object.hashAll(bounds),
    selectedText,
    note,
    colorValue,
    createdAt,
    modifiedAt,
  );
}

sealed class PdfEditFailure implements Exception {
  const PdfEditFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';

  List<Object?> get _equalityFields => <Object?>[code, message];

  @override
  bool operator ==(Object other) =>
      other is PdfEditFailure &&
      runtimeType == other.runtimeType &&
      _sameList(other._equalityFields, _equalityFields);

  @override
  int get hashCode =>
      Object.hashAll(<Object?>[runtimeType, ..._equalityFields]);
}

final class PdfReadOnlyTextBlockFailure extends PdfEditFailure {
  PdfReadOnlyTextBlockFailure({required this.locator, required this.reason})
    : super(
        'read_only_text_block',
        'This text block is read-only: ${reason.name}.',
      );

  final PdfTextBlockLocator locator;
  final PdfReadOnlyReason reason;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    locator,
    reason,
  ];
}

final class PdfUnsupportedTextOperationFailure extends PdfEditFailure {
  PdfUnsupportedTextOperationFailure({
    required this.locator,
    required this.capability,
  }) : super(
         'unsupported_text_operation',
         'This text block does not support ${capability.name}.',
       );

  final PdfTextBlockLocator locator;
  final PdfTextCapability capability;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    locator,
    capability,
  ];
}

final class PdfRevisionConflictFailure extends PdfEditFailure {
  const PdfRevisionConflictFailure({
    required this.expected,
    required this.actual,
  }) : super(
         'revision_conflict',
         'Expected revision $expected but found $actual.',
       );

  final String expected;
  final String actual;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    expected,
    actual,
  ];
}

final class PdfStaleLocatorFailure extends PdfEditFailure {
  const PdfStaleLocatorFailure(this.locator)
    : super(
        'stale_locator',
        'The text block no longer matches the source PDF.',
      );

  final PdfTextBlockLocator locator;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    locator,
  ];
}

final class PdfAmbiguousLocatorFailure extends PdfEditFailure {
  const PdfAmbiguousLocatorFailure(this.locator, this.candidateCount)
    : super(
        'ambiguous_locator',
        'The text block matches $candidateCount PDF objects.',
      );

  final PdfTextBlockLocator locator;
  final int candidateCount;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    locator,
    candidateCount,
  ];
}

final class PdfInvalidTextRangeFailure extends PdfEditFailure {
  const PdfInvalidTextRangeFailure({
    required this.range,
    required this.textLength,
  }) : super(
         'invalid_text_range',
         'The UTF-16 range is outside the text block.',
       );

  final PdfTextRange range;
  final int textLength;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    range,
    textLength,
  ];
}

final class PdfTextMismatchFailure extends PdfEditFailure {
  const PdfTextMismatchFailure({required this.locator, required this.expected})
    : super(
        'text_mismatch',
        'The text block no longer contains the expected text.',
      );

  final PdfTextBlockLocator locator;
  final String expected;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    locator,
    expected,
  ];
}

final class PdfTextOverflowFailure extends PdfEditFailure {
  const PdfTextOverflowFailure({required this.locator})
    : super('text_overflow', 'Text does not fit its box.');

  final PdfTextBlockLocator locator;

  @override
  List<Object?> get _equalityFields => <Object?>[
    ...super._equalityFields,
    locator,
  ];
}

final class PdfNativeEditingUnavailableFailure extends PdfEditFailure {
  const PdfNativeEditingUnavailableFailure()
    : super(
        'native_editing_unavailable',
        'Native PDF text editing is unavailable.',
      );
}

List<PdfTextRun> _mergeAdjacentRuns(List<PdfTextRun> runs) {
  final List<PdfTextRun> merged = <PdfTextRun>[];
  for (final PdfTextRun run in runs) {
    if (run.range.isEmpty) continue;
    if (merged.isNotEmpty) {
      final PdfTextRun previous = merged.last;
      if (previous.style == run.style &&
          previous.range.end == run.range.start) {
        merged[merged.length - 1] = PdfTextRun(
          range: PdfTextRange(previous.range.start, run.range.end),
          style: previous.style,
        );
        continue;
      }
    }
    merged.add(run);
  }
  return List<PdfTextRun>.unmodifiable(merged);
}

int _min(int left, int right) => left < right ? left : right;
int _max(int left, int right) => left > right ? left : right;

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameSet<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
