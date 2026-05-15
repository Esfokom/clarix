String resolveLocalModelPath(String relativePath) {
  throw UnsupportedError(
    'Local file model loading is not supported on web: $relativePath',
  );
}
