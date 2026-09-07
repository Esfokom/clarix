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
    if (uriString.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(uriString.trim());
      if (uri.scheme != scheme && !uriString.startsWith('clarix://')) return null;

      final path = uri.queryParameters['path'];
      final pageStr = uri.queryParameters['page'];
      if (path == null || path.trim().isEmpty || pageStr == null) return null;

      final page = int.tryParse(pageStr);
      if (page == null || page < 1) return null;

      final scrollStr = uri.queryParameters['scroll'];
      final scrollOffset = scrollStr != null ? double.tryParse(scrollStr) : null;

      return (
        filePath: path,
        page: page,
        scrollOffset: scrollOffset,
      );
    } catch (_) {
      return null;
    }
  }
}
