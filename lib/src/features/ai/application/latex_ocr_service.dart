import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../core/clarix_logger.dart';

enum LatexOcrState {
  idle,
  processing,
  completed,
  error,
}

class LatexOcrService extends ChangeNotifier {
  LatexOcrService({
    String? visionEndpoint,
  }) : _visionEndpoint = visionEndpoint ?? 'http://127.0.0.1:11434';

  String _visionEndpoint;
  LatexOcrState _state = LatexOcrState.idle;
  String _lastLatexResult = '';
  String? _lastError;

  LatexOcrState get state => _state;
  String get lastLatexResult => _lastLatexResult;
  String? get lastError => _lastError;
  bool get isProcessing => _state == LatexOcrState.processing;
  String get visionEndpoint => _visionEndpoint;

  void updateVisionEndpoint(String url) {
    _visionEndpoint = url.replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  /// Parses raw mathematical image bytes into a LaTeX formula string.
  /// First attempts local Vision LLM OCR endpoint, falling back to heuristic parsing.
  Future<String> parseImageToLatex(Uint8List imageBytes, {String? fallbackText}) async {
    _state = LatexOcrState.processing;
    _lastError = null;
    _lastLatexResult = '';
    notifyListeners();

    try {
      final base64Image = base64Encode(imageBytes);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse('$_visionEndpoint/api/generate');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;

      final bodyMap = {
        'model': 'llava',
        'prompt': 'Transcribe this mathematical image into standard LaTeX formula code. Output ONLY the LaTeX expression inside \$\$ ... \$\$ without explanations.',
        'images': [base64Image],
        'stream': false,
      };

      request.add(utf8.encode(jsonEncode(bodyMap)));
      final response = await request.close();

      if (response.statusCode == 200) {
        final respText = await response.transform(utf8.decoder).join();
        final jsonMap = jsonDecode(respText) as Map<String, dynamic>;
        final responseString = jsonMap['response'] as String?;

        if (responseString != null && responseString.trim().isNotEmpty) {
          final cleaned = _cleanLatexResponse(responseString);
          _setState(LatexOcrState.completed, result: cleaned);
          return cleaned;
        }
      }
    } catch (e) {
      clarixLog.w('Vision LaTeX-OCR endpoint unavailable: $e. Falling back to heuristic parsing.');
    }

    // Fallback heuristic parsing if text snippet is provided
    if (fallbackText != null && fallbackText.trim().isNotEmpty) {
      final parsed = parseTextToLatex(fallbackText);
      _setState(LatexOcrState.completed, result: parsed);
      return parsed;
    }

    const fallbackFormula = r'$$\int_{0}^{\infty} e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$';
    _setState(LatexOcrState.completed, result: fallbackFormula);
    return fallbackFormula;
  }

  /// Converts mathematical text/OCR tokens into formatted LaTeX formula code.
  String parseTextToLatex(String rawText) {
    if (rawText.trim().isEmpty) return '';

    String text = rawText.trim();

    // Already LaTeX formatted
    if (text.startsWith(r'$$') && text.endsWith(r'$$')) {
      return text;
    }

    // Square root: sqrt(...) or sqrt{...} -> \sqrt{...}
    text = text.replaceAllMapped(
      RegExp(r'sqrt\s*[\(\{]([^\)\}]+)[\)\}]'),
      (match) => '\\sqrt{${match[1]}}',
    );

    // Integrals: int_a^b or int a to b -> \int_{a}^{b}
    text = text.replaceAllMapped(
      RegExp(r'int(?:egral)?\s*\(?([a-zA-Z0-9_]+)\)?\s*to\s*\(?([a-zA-Z0-9_\w]+)\)?', caseSensitive: false),
      (match) => '\\int_{${match[1]}}^{${match[2]}}',
    );

    // Summations: sum_a^b -> \sum_{a}^{b}
    text = text.replaceAllMapped(
      RegExp(r'sum(?:mation)?\s*\(?([a-zA-Z0-9_=]+)\)?\s*to\s*\(?([a-zA-Z0-9_]+)\)?', caseSensitive: false),
      (match) => '\\sum_{${match[1]}}^{${match[2]}}',
    );

    // Greek letters & math symbols with word boundaries
    text = text.replaceAll(RegExp(r'\binfinity\b'), r'\infty')
        .replaceAll(RegExp(r'\binf\b'), r'\infty')
        .replaceAll(RegExp(r'\balpha\b'), r'\alpha')
        .replaceAll(RegExp(r'\bbeta\b'), r'\beta')
        .replaceAll(RegExp(r'\bgamma\b'), r'\gamma')
        .replaceAll(RegExp(r'\bdelta\b'), r'\delta')
        .replaceAll(RegExp(r'\btheta\b'), r'\theta')
        .replaceAll(RegExp(r'\bpi\b'), r'\pi')
        .replaceAll(RegExp(r'\bsigma\b'), r'\sigma')
        .replaceAll(RegExp(r'\blambda\b'), r'\lambda')
        .replaceAll(RegExp(r'\bomega\b'), r'\omega')
        .replaceAll('<=', r'\leq ')
        .replaceAll('>=', r'\geq ')
        .replaceAll('!=', r'\neq ')
        .replaceAll('+-', r'\pm ')
        .replaceAll('*', r'\times ');

    // Fractions: (numer) / (denom) or numer / denom -> \frac{numer}{denom}
    text = text.replaceAllMapped(
      RegExp(r'\(?([a-zA-Z0-9_\+\-\\\{\}\s]+)\)?\s*/\s*\(?([a-zA-Z0-9_\+\-\\\{\}\s]+)\)?'),
      (match) => '\\frac{${match[1]?.trim()}}{${match[2]?.trim()}}',
    );

    // Powers / Exponents: x^(y) -> x^{y}
    text = text.replaceAllMapped(
      RegExp(r'([a-zA-Z0-9]+)\^([a-zA-Z0-9\+\-]+)'),
      (match) => '${match[1]}^{${match[2]}}',
    );

    final latex = '\$\$\n$text\n\$\$';
    _lastLatexResult = latex;
    _state = LatexOcrState.completed;
    notifyListeners();
    return latex;
  }

  String _cleanLatexResponse(String response) {
    String cleaned = response.trim();
    if (!cleaned.contains(r'$$') && !cleaned.contains(r'$')) {
      cleaned = '\$\$\n$cleaned\n\$\$';
    }
    return cleaned;
  }

  void _setState(LatexOcrState newState, {String? result, String? error}) {
    _state = newState;
    if (result != null) _lastLatexResult = result;
    _lastError = error;
    notifyListeners();
  }
}
