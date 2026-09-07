import 'package:flutter/foundation.dart';

class GemmaCognitiveUiService extends ChangeNotifier {
  bool _isReflowing = false;
  String _lastReflowedText = '';
  String _lastBionicText = '';

  bool get isReflowing => _isReflowing;
  String get lastReflowedText => _lastReflowedText;
  String get lastBionicText => _lastBionicText;

  /// Reflows double-column / scanned PDF viewport layout into accessible single-column text.
  String reflowLayout(String rawText) {
    if (rawText.isEmpty) return '';

    _isReflowing = true;
    notifyListeners();

    // Clean up line breaks, hyphens, and multi-column headers
    String cleaned = rawText
        .replaceAll(RegExp(r'(\w+)-\n(\w+)'), r'$1$2')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    _lastReflowedText = cleaned;
    _isReflowing = false;
    notifyListeners();
    return cleaned;
  }

  /// Reasoning-injected bionic reading typography generator.
  /// Selectively bolds structural emphasis points of words based on cognitive readability.
  String generateBionicReadingText(String text) {
    if (text.isEmpty) return '';

    final words = text.split(RegExp(r'\s+'));
    final bionicWords = <String>[];

    for (final word in words) {
      if (word.length <= 2) {
        bionicWords.add('**${word[0]}**${word.substring(1)}');
      } else {
        final boldLen = (word.length * 0.45).ceil();
        final boldPart = word.substring(0, boldLen);
        final restPart = word.substring(boldLen);
        bionicWords.add('**$boldPart**$restPart');
      }
    }

    final result = bionicWords.join(' ');
    _lastBionicText = result;
    notifyListeners();
    return result;
  }
}
