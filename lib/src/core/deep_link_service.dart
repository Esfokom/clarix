/// Deep-Linking Protocol Service for Clarix
/// Generates and parses native `clarix://` URI schemes to link directly
/// to specific pages and scroll positions inside PDF documents.
class DeepLinkService {
  const DeepLinkService();

  static const String scheme = 'clarix';
  static const String hostOpen = 'open';

  /// Generates a standardized deep-link URI string:
  /// `clarix://open?path=c%3A%2Fdocs%2Fsample.pdf&page=42&scroll=0.5`
  String generateDeepLink({
    required String filePath,
    required int page,
    double? scrollOffset,
  }) {
    final params = <String, String>{
      'path': filePath,
      'page': page.toString(),
    };
    if (scrollOffset != null) {
      params['scroll'] = scrollOffset.toStringAsFixed(3);
    }
    final uri = Uri(
      scheme: scheme,
      host: hostOpen,
      queryParameters: params,
    );
    return uri.toString();
  }

  /// Parses a deep-link URI string into its document location components
  ({String filePath, int page, double? scrollOffset})? parseDeepLink(String uriString) {
    final raw = uriString.trim();
    if (raw.isEmpty) return null;
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme != scheme && !raw.toLowerCase().startsWith('clarix://')) {
        return null;
      }

      final path = uri.queryParameters['path'] ?? uri.queryParameters['file'];
      final pageStr = uri.queryParameters['page'] ?? uri.queryParameters['p'];
      if (path == null || path.trim().isEmpty || pageStr == null) return null;

      final decodedPath = Uri.decodeComponent(path.trim());
      final page = int.tryParse(pageStr.trim());
      if (page == null || page < 1) return null;

      final scrollStr = uri.queryParameters['scroll'] ?? uri.queryParameters['offset'];
      double? scrollOffset = scrollStr != null ? double.tryParse(scrollStr.trim()) : null;
      if (scrollOffset != null && (scrollOffset.isNaN || scrollOffset.isInfinite)) {
        scrollOffset = null;
      } else if (scrollOffset != null) {
        scrollOffset = scrollOffset.clamp(0.0, 1.0);
      }

      return (
        filePath: decodedPath,
        page: page,
        scrollOffset: scrollOffset,
      );
    } catch (_) {
      return null;
    }
  }
}
