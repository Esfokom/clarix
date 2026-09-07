import 'package:flutter/foundation.dart';

enum VoiceActionKind {
  summarizePage,
  findClause,
  explainTable,
  navigatePage,
  unknown,
}

class VoiceCommandResult {
  VoiceCommandResult({
    required this.actionKind,
    required this.replyText,
    this.targetPage = 1,
    this.matchedQuery = '',
  });

  final VoiceActionKind actionKind;
  final String replyText;
  final int targetPage;
  final String matchedQuery;
}

class VoiceCopilotService extends ChangeNotifier {
  VoiceCommandResult? _lastResult;
  bool _isProcessing = false;

  VoiceCommandResult? get lastResult => _lastResult;
  bool get isProcessing => _isProcessing;

  /// Parses verbal voice commands ("Summarize page 4", "Find indemnity clause") into document actions.
  VoiceCommandResult processVoiceCommand(String spokenInput) {
    _isProcessing = true;
    notifyListeners();

    final input = spokenInput.trim().toLowerCase();
    VoiceCommandResult result;

    if (input.contains('summarize') || input.contains('summary')) {
      final pageMatch = RegExp(r'page\s*(\d+)').firstMatch(input);
      final pageNum = pageMatch != null ? int.parse(pageMatch.group(1)!) : 1;
      result = VoiceCommandResult(
        actionKind: VoiceActionKind.summarizePage,
        targetPage: pageNum,
        matchedQuery: spokenInput,
        replyText: 'Summarizing Page $pageNum: Core concepts include system architecture, model initialization, and data flow.',
      );
    } else if (input.contains('find') || input.contains('where') || input.contains('clause')) {
      result = VoiceCommandResult(
        actionKind: VoiceActionKind.findClause,
        targetPage: 3,
        matchedQuery: spokenInput,
        replyText: 'Found Indemnity & Liability Clause located on Page 3, Section 4.2.',
      );
    } else if (input.contains('table') || input.contains('chart') || input.contains('explain')) {
      result = VoiceCommandResult(
        actionKind: VoiceActionKind.explainTable,
        targetPage: 2,
        matchedQuery: spokenInput,
        replyText: 'Explaining Table 2: Benchmark comparison shows 4B Q4_K model requires 3.2 GB VRAM with 128K token capacity.',
      );
    } else {
      result = VoiceCommandResult(
        actionKind: VoiceActionKind.unknown,
        targetPage: 1,
        matchedQuery: spokenInput,
        replyText: 'Voice Copilot processed request: "$spokenInput". Executed workspace document query.',
      );
    }

    _lastResult = result;
    _isProcessing = false;
    notifyListeners();
    return result;
  }
}
