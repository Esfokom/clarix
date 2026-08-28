/// The smallest edit that turns [before] into [after], as UTF-16 code units.
({int start, int end, String replacement}) computeTextDelta(
  String before,
  String after,
) {
  final oldUnits = before.codeUnits;
  final newUnits = after.codeUnits;
  var prefix = 0;
  while (prefix < oldUnits.length &&
      prefix < newUnits.length &&
      oldUnits[prefix] == newUnits[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldUnits.length - prefix &&
      suffix < newUnits.length - prefix &&
      oldUnits[oldUnits.length - suffix - 1] ==
          newUnits[newUnits.length - suffix - 1]) {
    suffix++;
  }
  return (
    start: prefix,
    end: oldUnits.length - suffix,
    replacement: String.fromCharCodes(
      newUnits.sublist(prefix, newUnits.length - suffix),
    ),
  );
}
