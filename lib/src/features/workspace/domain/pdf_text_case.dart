enum PdfReplacementCase {
  upper,
  lower,
  title,
  sentence,
  mixed;

  static PdfReplacementCase detect(String source) {
    final String letters = source.replaceAll(
      RegExp(r'[^\p{L}]', unicode: true),
      '',
    );
    if (letters.isEmpty) return PdfReplacementCase.mixed;
    if (letters == letters.toUpperCase()) return PdfReplacementCase.upper;
    if (letters == letters.toLowerCase()) return PdfReplacementCase.lower;

    final List<String> words = source
        .split(RegExp(r'\s+', unicode: true))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isNotEmpty && words.every(_isTitleWord)) {
      return PdfReplacementCase.title;
    }
    if (_isSentenceCase(source)) return PdfReplacementCase.sentence;
    return PdfReplacementCase.mixed;
  }

  String apply(String replacement) => switch (this) {
    PdfReplacementCase.upper => replacement.toUpperCase(),
    PdfReplacementCase.lower => replacement.toLowerCase(),
    PdfReplacementCase.title => _toTitleCase(replacement),
    PdfReplacementCase.sentence => _toSentenceCase(replacement),
    PdfReplacementCase.mixed => replacement,
  };
}

String matchReplacementCase(String source, String replacement) =>
    PdfReplacementCase.detect(source).apply(replacement);

bool _isTitleWord(String word) {
  final Match? firstLetter = RegExp(r'\p{L}', unicode: true).firstMatch(word);
  if (firstLetter == null) return true;
  final String first = firstLetter.group(0)!;
  final String tail = word
      .substring(firstLetter.end)
      .replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  return first == first.toUpperCase() && tail == tail.toLowerCase();
}

bool _isSentenceCase(String value) {
  final Match? firstLetter = RegExp(r'\p{L}', unicode: true).firstMatch(value);
  if (firstLetter == null) return false;
  final String first = firstLetter.group(0)!;
  final String tail = value
      .substring(firstLetter.end)
      .replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  return first == first.toUpperCase() && tail == tail.toLowerCase();
}

String _toTitleCase(String value) => value.replaceAllMapped(
  RegExp(r'\p{L}[\p{L}\p{M}]*', unicode: true),
  (Match match) {
    final String word = match.group(0)!;
    return '${word.substring(0, 1).toUpperCase()}'
        '${word.substring(1).toLowerCase()}';
  },
);

String _toSentenceCase(String value) {
  final String lowered = value.toLowerCase();
  final Match? firstLetter = RegExp(
    r'\p{L}',
    unicode: true,
  ).firstMatch(lowered);
  if (firstLetter == null) return lowered;
  return '${lowered.substring(0, firstLetter.start)}'
      '${firstLetter.group(0)!.toUpperCase()}'
      '${lowered.substring(firstLetter.end)}';
}
