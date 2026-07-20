import 'dart:collection';

class AiProviderProfile {
  AiProviderProfile({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.modelId,
    required this.shareRetrievedPassages,
    required Map<String, String> headers,
  }) : headers = UnmodifiableMapView<String, String>(headers);

  factory AiProviderProfile.create({
    required String id,
    required String label,
    required String baseUrl,
    required String modelId,
    required bool shareRetrievedPassages,
    Map<String, String> headers = const <String, String>{},
  }) {
    final String normalizedId = id.trim();
    final String normalizedLabel = label.trim();
    final String normalizedModel = modelId.trim();
    final String normalizedUrl = _normalizeUrl(baseUrl);
    if (normalizedId.isEmpty || normalizedLabel.isEmpty || normalizedModel.isEmpty) {
      throw ArgumentError('Provider ID, label, and model are required.');
    }
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.trim().isEmpty || header.value.trim().isEmpty) {
        throw ArgumentError('Custom headers must have a name and value.');
      }
      if (header.key.toLowerCase() == 'authorization') {
        throw ArgumentError('Authorization is managed by the provider API key.');
      }
    }
    return AiProviderProfile(
      id: normalizedId,
      label: normalizedLabel,
      baseUrl: normalizedUrl,
      modelId: normalizedModel,
      shareRetrievedPassages: shareRetrievedPassages,
      headers: headers,
    );
  }

  factory AiProviderProfile.fromJson(Map<String, dynamic> json) {
    final Object? rawHeaders = json['headers'];
    final Map<String, String> headers = rawHeaders is Map
        ? rawHeaders.map<String, String>(
            (Object? key, Object? value) => MapEntry(key! as String, value! as String),
          )
        : const <String, String>{};
    return AiProviderProfile.create(
      id: json['id'] as String,
      label: json['label'] as String,
      baseUrl: json['baseUrl'] as String,
      modelId: json['modelId'] as String,
      shareRetrievedPassages: json['shareRetrievedPassages'] as bool? ?? false,
      headers: headers,
    );
  }

  final String id;
  final String label;
  final String baseUrl;
  final String modelId;
  final bool shareRetrievedPassages;
  final Map<String, String> headers;

  Uri get normalizedBaseUri => Uri.parse(baseUrl);
  Uri get chatCompletionsUri => normalizedBaseUri.resolve('chat/completions');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'baseUrl': baseUrl,
        'modelId': modelId,
        'shareRetrievedPassages': shareRetrievedPassages,
        'headers': headers,
      };

  static String _normalizeUrl(String rawUrl) {
    final Uri? uri = Uri.tryParse(rawUrl.trim());
    final bool localHttp = uri?.scheme == 'http' &&
        (uri?.host == 'localhost' || uri?.host == '127.0.0.1');
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'https' && !localHttp)) {
      throw ArgumentError('Provider URLs must use HTTPS, except localhost endpoints.');
    }
    final String path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path).toString();
  }

  @override
  bool operator ==(Object other) =>
      other is AiProviderProfile &&
      other.id == id &&
      other.label == label &&
      other.baseUrl == baseUrl &&
      other.modelId == modelId &&
      other.shareRetrievedPassages == shareRetrievedPassages &&
      _mapsEqual(other.headers, headers);

  @override
  int get hashCode => Object.hash(
        id,
        label,
        baseUrl,
        modelId,
        shareRetrievedPassages,
        Object.hashAll(headers.entries),
      );

  static bool _mapsEqual(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    return left.entries.every((MapEntry<String, String> entry) => right[entry.key] == entry.value);
  }
}
