import 'dart:ui';

class OcrWordData {
  const OcrWordData({
    required this.text,
    required this.confidence,
    required this.bounds,
  });

  factory OcrWordData.fromJson(Map<String, dynamic> json) {
    final bounds = json['bounds'] as Map<String, dynamic>;
    return OcrWordData(
      text: json['text'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      bounds: Rect.fromLTRB(
        (bounds['left'] as num).toDouble(),
        (bounds['top'] as num).toDouble(),
        (bounds['right'] as num).toDouble(),
        (bounds['bottom'] as num).toDouble(),
      ),
    );
  }

  final String text;
  final double confidence;
  final Rect bounds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'confidence': confidence,
    'bounds': <String, double>{
      'left': bounds.left,
      'top': bounds.top,
      'right': bounds.right,
      'bottom': bounds.bottom,
    },
  };
}

class OcrPageData {
  const OcrPageData({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.modelId,
    required this.words,
  });

  factory OcrPageData.fromJson(Map<String, dynamic> json) => OcrPageData(
    pageNumber: json['pageNumber'] as int,
    width: json['width'] as int,
    height: json['height'] as int,
    modelId: json['modelId'] as String,
    words: (json['words'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => OcrWordData.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );

  final int pageNumber;
  final int width;
  final int height;
  final String modelId;
  final List<OcrWordData> words;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'pageNumber': pageNumber,
    'width': width,
    'height': height,
    'modelId': modelId,
    'words': words.map((word) => word.toJson()).toList(growable: false),
  };
}
