/// Workflows supported by the local document utilities.
enum UtilityFormat {
  combine,
  convertToPdf,
  extractPages,
  markdown,
  word,
  powerpoint,
}

/// Immutable progress information for a running utility workflow.
final class UtilityJob {
  const UtilityJob({required this.format, required this.progress, this.message})
    : assert(progress >= 0 && progress <= 1);

  final UtilityFormat format;
  final double progress;
  final String? message;
}

/// The output created by a completed utility workflow.
final class UtilityResult {
  const UtilityResult({required this.outputPath, required this.pageCount});

  final String outputPath;
  final int pageCount;
}

/// An actionable, expected failure from a utility workflow.
final class UtilityFailure implements Exception {
  const UtilityFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
