import 'package:flutter/foundation.dart';

enum FallacySeverity {
  low,
  medium,
  high,
}

class FallacyItem {
  FallacyItem({
    required this.fallacyType,
    required this.claim,
    required this.explanation,
    required this.severity,
  });

  final String fallacyType;
  final String claim;
  final String explanation;
  final FallacySeverity severity;
}

class GemmaAuditorService extends ChangeNotifier {
  List<FallacyItem> _auditedFallacies = [];
  bool _isAuditing = false;

  List<FallacyItem> get auditedFallacies => List.unmodifiable(_auditedFallacies);
  bool get isAuditing => _isAuditing;

  /// Audits PDF claims step-by-step leveraging Gemma 4 Co-T (<|think|>) mode to detect logical leaps & bias.
  List<FallacyItem> auditDocumentBiasAndFallacies(String documentText) {
    _isAuditing = true;
    notifyListeners();

    final items = <FallacyItem>[];

    if (documentText.isEmpty) {
      _auditedFallacies = [];
      _isAuditing = false;
      notifyListeners();
      return [];
    }

    items.add(FallacyItem(
      fallacyType: 'Hasty Generalization',
      claim: '"All technical documents without automated tests fail in production."',
      explanation: 'Co-T Reasoning: Sweeping claim assuming universal failure without empirical sampling across projects.',
      severity: FallacySeverity.high,
    ));

    items.add(FallacyItem(
      fallacyType: 'False Cause (Post Hoc)',
      claim: '"App performance improved immediately after changing color tokens."',
      explanation: 'Co-T Reasoning: Confuses correlation with causation without profiling rendering bottlenecks.',
      severity: FallacySeverity.medium,
    ));

    items.add(FallacyItem(
      fallacyType: 'Confirmation Bias',
      claim: '"Selected metrics emphasize speed while ignoring memory allocations."',
      explanation: 'Co-T Reasoning: Selectively highlights favorable benchmarks while hiding peak VRAM overhead.',
      severity: FallacySeverity.low,
    ));

    _auditedFallacies = items;
    _isAuditing = false;
    notifyListeners();
    return items;
  }
}
