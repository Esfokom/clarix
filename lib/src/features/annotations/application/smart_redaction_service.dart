import 'package:flutter/foundation.dart';

enum RedactionCategory {
  ssn,
  email,
  creditCard,
  phone,
  names,
  financial,
}

class RedactionMatch {
  const RedactionMatch({
    required this.category,
    required this.matchedText,
    required this.startIndex,
    required this.endIndex,
    this.reason,
  });

  final RedactionCategory category;
  final String matchedText;
  final int startIndex;
  final int endIndex;
  final String? reason;
}

class SmartRedactionService extends ChangeNotifier {
  List<RedactionMatch> _lastMatches = [];
  bool _isScanning = false;

  List<RedactionMatch> get lastMatches => List.unmodifiable(_lastMatches);
  bool get isScanning => _isScanning;

  /// Scans text content for sensitive PII based on selected categories.
  List<RedactionMatch> scanDocumentForPii(
    String text, {
    Set<RedactionCategory>? categories,
  }) {
    _isScanning = true;
    notifyListeners();

    final selected = categories ?? RedactionCategory.values.toSet();
    final matches = <RedactionMatch>[];

    if (text.isEmpty) {
      _lastMatches = [];
      _isScanning = false;
      notifyListeners();
      return [];
    }

    // 1. Social Security Numbers (SSN): 000-00-0000 or 9 digits
    if (selected.contains(RedactionCategory.ssn)) {
      final ssnRegex = RegExp(r'\b\d{3}-\d{2}-\d{4}\b');
      for (final match in ssnRegex.allMatches(text)) {
        matches.add(RedactionMatch(
          category: RedactionCategory.ssn,
          matchedText: match.group(0)!,
          startIndex: match.start,
          endIndex: match.end,
          reason: 'Social Security Number (SSN)',
        ));
      }
    }

    // 2. Email Addresses
    if (selected.contains(RedactionCategory.email)) {
      final emailRegex = RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');
      for (final match in emailRegex.allMatches(text)) {
        matches.add(RedactionMatch(
          category: RedactionCategory.email,
          matchedText: match.group(0)!,
          startIndex: match.start,
          endIndex: match.end,
          reason: 'Email Address',
        ));
      }
    }

    // 3. Credit Cards & Bank Account Numbers
    if (selected.contains(RedactionCategory.creditCard)) {
      final ccRegex = RegExp(r'\b(?:\d[ -]*?){13,16}\b');
      for (final match in ccRegex.allMatches(text)) {
        final digitsOnly = match.group(0)!.replaceAll(RegExp(r'\D'), '');
        if (digitsOnly.length >= 13 && digitsOnly.length <= 19) {
          matches.add(RedactionMatch(
            category: RedactionCategory.creditCard,
            matchedText: match.group(0)!,
            startIndex: match.start,
            endIndex: match.end,
            reason: 'Credit Card / Account Number',
          ));
        }
      }
    }

    // 4. Phone Numbers
    if (selected.contains(RedactionCategory.phone)) {
      final phoneRegex = RegExp(r'\b(?:\+?\d{1,3}[ -]?)?\(?\d{3}\)?[ -]?\d{3}[ -]?\d{4}\b');
      for (final match in phoneRegex.allMatches(text)) {
        matches.add(RedactionMatch(
          category: RedactionCategory.phone,
          matchedText: match.group(0)!,
          startIndex: match.start,
          endIndex: match.end,
          reason: 'Phone Number',
        ));
      }
    }

    // 5. Financial Figures (e.g. $1,234.56, USD 50,000, Balance: 9,000)
    if (selected.contains(RedactionCategory.financial)) {
      final finRegex = RegExp(r'(?:\$|USD|EUR|GBP)\s?\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\b(?:Balance|Amount|Paid|Cost|Salary)\s*:?\s*\$?\d+(?:\.\d{2})?\b', caseSensitive: false);
      for (final match in finRegex.allMatches(text)) {
        matches.add(RedactionMatch(
          category: RedactionCategory.financial,
          matchedText: match.group(0)!,
          startIndex: match.start,
          endIndex: match.end,
          reason: 'Financial Amount / Balance',
        ));
      }
    }

    // 6. Person Names & Header NER (e.g. Name: John Doe, Patient: Jane Smith)
    if (selected.contains(RedactionCategory.names)) {
      final nameRegex = RegExp(r'\b(?:Name|Patient|Client|Employee|User|Author)\s*:\s*([A-Z][a-z]+\s+[A-Z][a-z]+)\b');
      for (final match in nameRegex.allMatches(text)) {
        matches.add(RedactionMatch(
          category: RedactionCategory.names,
          matchedText: match.group(0)!,
          startIndex: match.start,
          endIndex: match.end,
          reason: 'Person Name / Identity',
        ));
      }
    }

    // Sort matches by start index
    matches.sort((a, b) => a.startIndex.compareTo(b.startIndex));

    _lastMatches = matches;
    _isScanning = false;
    notifyListeners();
    return matches;
  }

  /// Replaces detected PII matches with blacked-out mask blocks (█████████).
  String generateRedactedText(String sourceText, List<RedactionMatch> matches) {
    if (sourceText.isEmpty || matches.isEmpty) return sourceText;

    final sorted = List<RedactionMatch>.from(matches)..sort((a, b) => a.startIndex.compareTo(b.startIndex));
    final buffer = StringBuffer();
    int current = 0;

    for (final m in sorted) {
      if (m.startIndex < current) continue; // Skip overlapping
      buffer.write(sourceText.substring(current, m.startIndex));
      final maskLength = m.matchedText.length;
      buffer.write('█' * maskLength);
      current = m.endIndex;
    }

    if (current < sourceText.length) {
      buffer.write(sourceText.substring(current));
    }

    return buffer.toString();
  }
}
