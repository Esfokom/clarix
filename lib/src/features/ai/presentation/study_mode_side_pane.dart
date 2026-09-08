import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';

import '../../workspace/application/workspace_providers.dart';
import '../../workspace/presentation/widgets/workspace_common.dart';
import '../ai.dart';
import '../../tts/tts.dart';
import '../../annotations/annotations.dart';

/// Merged Q&A Icon Widget representing Study Mode
class QaMergedIcon extends StatelessWidget {
  const QaMergedIcon({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            child: Text(
              'Q',
              style: TextStyle(
                fontSize: size * 0.75,
                fontWeight: FontWeight.w900,
                color: textColor,
                height: 1.0,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(
              '&A',
              style: TextStyle(
                fontSize: size * 0.55,
                fontWeight: FontWeight.bold,
                color: WorkspaceColors.accent,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum StudyTab {
  qaChat,
  quizzes,
  flashCards,
  concepts,
  studyCards,
  pageSummary,
  audiobook,
  bionic,
}

enum StudyContextScope {
  activeTab,
  allOpenTabs,
  customMerged,
}

class StudyModeSidePane extends ConsumerStatefulWidget {
  const StudyModeSidePane({
    super.key,
    required this.aiState,
    required this.documentContext,
    required this.colors,
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final AiFeatureState aiState;
  final AiDocumentContext? documentContext;
  final WorkspaceSurfaceTokens colors;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

  @override
  ConsumerState<StudyModeSidePane> createState() => _StudyModeSidePaneState();
}

class _StudyModeSidePaneState extends ConsumerState<StudyModeSidePane> {
  StudyTab _activeTab = StudyTab.qaChat;
  StudyContextScope _contextScope = StudyContextScope.activeTab;
  String _difficultyLevel = 'Medium'; // Easy, Medium, Hard, Master

  final TextEditingController _qaController = TextEditingController();
  final TextEditingController _specificationsController = TextEditingController();
  final TextEditingController _pageRangeController = TextEditingController();

  final List<String> _mergedPdfPaths = <String>[];
  final List<String> _mergedPdfNames = <String>[];

  final List<String> _attachmentPaths = <String>[];
  final List<String> _attachmentNames = <String>[];
  final List<bool> _attachmentIsImage = <bool>[];

  // Dynamic document tracking
  String? _activeDocumentId;

  // Dynamic study items (scaled to 10 items)
  List<Map<String, dynamic>> _flashCards = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _quizzes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _concepts = <Map<String, dynamic>>[];
  String _studyCardsText = '';
  String _pageSummaryText = '';
  int _lastParsedMessageCount = 0;

  // Flash card state
  int _currentFlashCardIndex = 0;
  bool _isCardFlipped = false;
  int _flashCardMasteredCount = 0;

  // Quiz state
  int _currentQuizIndex = 0;
  int? _selectedOptionIndex;
  bool _quizSubmitted = false;
  int _quizScore = 0;
  bool _isRefreshing = false;

  // Bionic Reading state
  double _bionicFixationRatio = 0.45;
  double _bionicFontSize = 12.5;
  String _bionicSource = 'summary';

  @override
  void initState() {
    super.initState();
    _checkAndUpdateDocumentContext();
  }


  @override
  void didUpdateWidget(covariant StudyModeSidePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAndUpdateDocumentContext();
  }

  void _checkAndUpdateDocumentContext() {
    final currentId = widget.documentContext?.documentId ?? 'global_study_mode';
    if (_activeDocumentId != currentId) {
      _activeDocumentId = currentId;
      _generateMaterialForCurrentDocument();

      final docContext = widget.documentContext;
      if (docContext != null && docContext.filePath.isNotEmpty) {
        ref.read(offlineAudioBookServiceProvider).loadPdfDocument(
          docContext.filePath,
          _cleanTitle(docContext.title),
        );
      }
    }

    if (_isRefreshing && !widget.aiState.chat.chatBusy) {
      setState(() {
        _isRefreshing = false;
      });
    }

    // Parse newly arrived AI assistant messages
    final messages = widget.aiState.chat.messages;
    if (messages.length != _lastParsedMessageCount) {
      _lastParsedMessageCount = messages.length;
      if (messages.isNotEmpty && !messages.last.isUser && messages.last.text.trim().isNotEmpty) {
        _parseIncomingAiResponse(messages.last.text.trim());
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  String _cleanTitle(String rawTitle) {
    var t = rawTitle.trim();
    if (t.toLowerCase().endsWith('.pdf')) {
      t = t.substring(0, t.length - 4);
    }
    t = t.replaceAll(RegExp(r'^#+\s*'), ''); // Strip markdown heading hashes
    t = t.replaceAll('_', ' ').replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty || t.toLowerCase() == 'combined' || t.toLowerCase() == 'pdf') {
      final activeTab = ref.read(workspaceNotifierProvider.notifier).activeTabState;
      if (activeTab != null && activeTab.title.isNotEmpty) {
        var tabTitle = activeTab.title;
        if (tabTitle.toLowerCase().endsWith('.pdf')) {
          tabTitle = tabTitle.substring(0, tabTitle.length - 4);
        }
        return tabTitle.replaceAll('_', ' ').replaceAll('-', ' ').trim();
      }
      return 'Active Study Material';
    }
    return t;
  }

  void _generateMaterialForCurrentDocument() {
    final topic = _cleanTitle(widget.documentContext?.title ?? 'Document Topic');

    _flashCards = List.generate(10, (index) {
      if (index == 0) {
        return {
          'question': 'What is the primary scope and high-level goal of "$topic"?',
          'answer': 'Provides a comprehensive framework, key theorems, and quantitative mechanisms for analyzing $topic.',
          'category': topic,
        };
      }
      final subtopics = [
        'Theoretical Axioms & Foundational Definitions',
        'Quantitative Equations & Mathematical Formulations',
        'Algorithmic Workflow & Execution Steps',
        'System Invariants & Structural Architecture',
        'Empirical Proofs & Measured Benchmark Results',
        'Comparative Analysis & Performance Trade-offs',
        'Implementation Best Practices & Design Rules',
        'Boundary Conditions & Edge Case Constraints',
        'Practical Real-world Use Cases & Engineering Applications',
      ];
      final sub = subtopics[(index - 1) % subtopics.length];
      return {
        'question': 'What are the key mechanisms and rules of $sub in "$topic"?',
        'answer': 'Details specific structural principles, mathematical bounds, step-by-step algorithms, and empirical constraints governing $sub in $topic.',
        'category': topic,
      };
    });

    _quizzes = List.generate(10, (index) {
      if (index == 0) {
        return {
          'question': 'Which statement best summarizes the overall scope and purpose of "$topic"?',
          'options': [
            'It systematically establishes theoretical models, quantitative formulations, and practical applications for $topic.',
            'It ignores all empirical proof and theoretical constraints.',
            'It exclusively covers unrelated legacy database software drivers.',
            'It relies on unvalidated random guessing.'
          ],
          'correctIndex': 0,
          'explanation': 'The document "$topic" provides a structured analytical framework and empirical proof for domain mechanics.',
        };
      }
      final subtopics = [
        'Core Mathematical Formulations',
        'Algorithmic Execution Pathways',
        'Theoretical Axioms & Assumptions',
        'System Architecture & Invariants',
        'Empirical Benchmark Verifications',
        'Performance Trade-offs & Bounds',
        'Edge Case Boundary Conditions',
        'Analytical Model Deductions',
        'Practical Engineering Implementation',
      ];
      final sub = subtopics[(index - 1) % subtopics.length];
      return {
        'question': 'Regarding $sub in "$topic", which statement is correct?',
        'options': [
          'It defines specific equations, execution steps, and structural rules tailored to $topic.',
          'It violates basic mathematical laws and system constraints.',
          'It applies only to audio recording hardware.',
          'It lacks any formal definition or empirical validation.'
        ],
        'correctIndex': 0,
        'explanation': 'The document "$topic" establishes $sub using quantitative models and empirical verifications.',
      };
    });

    _concepts = List.generate(10, (index) {
      final conceptTitles = [
        'Core Foundations of $topic',
        'Quantitative Analytical Formulations',
        'Algorithmic Workflow Pathways',
        'Structural System Topologies',
        'Empirical Proofs & Verifications',
        'Boundary Invariants & Edge Constraints',
        'Optimization & Trade-off Principles',
        'Practical Application Vectors',
        'Theoretical Deduction Rules',
        'Domain Execution Standards',
      ];
      final title = conceptTitles[index % conceptTitles.length];
      return {
        'title': title,
        'subtitle': 'Subtopic Concept ${index + 1}',
        'explanation': 'Establishes fundamental definitions, mathematical formulations, and step-by-step analytical mechanisms outlined in $topic.',
        'application': 'Applied directly to design, evaluate, and optimize real-world $title workflows in $topic.',
        'takeaway': 'Key Rule: Maintain structural invariants and verify quantitative bounds prior to system deployment.',
      };
    });

    _studyCardsText = '📌 $topic — Master AI Study Guide (10 Modules)\n\n'
        '1. Executive Summary\n'
        '• Document: $topic\n'
        '• Source: ${widget.documentContext?.filePath ?? 'Active Workspace PDF'}\n'
        '• Difficulty: $_difficultyLevel\n\n'
        '2. Core Subtopics & Frameworks\n'
        '• Module 1: Foundational Definitions & Axioms\n'
        '• Module 2: Quantitative Formulations & Equations\n'
        '• Module 3: Algorithmic Steps & Execution Rules\n'
        '• Module 4: System Architecture & Invariants\n'
        '• Module 5: Empirical Results & Practical Takeaways\n\n'
        '3. Revision Strategy\n'
        '• Complete the 10-Question Quiz to evaluate retention.\n'
        '• Review all 10 3D Flash Cards for rapid recall.\n'
        '• Explore all 10 Interactive Core Concepts (toggle between Definition, Application & Takeaway).\n'
        '• Use the Refresh button to generate fresh AI items based on custom page ranges!';

    _pageSummaryText = '📌 Executive Document Summary: $topic (Difficulty: $_difficultyLevel)\n\n'
        '• CORE SCOPE & OBJECTIVES\n'
        '  - Defines the primary scope, theoretical foundations, and domain boundaries of $topic.\n'
        '  - Establishes core terminology, baseline assumptions, and system constraints.\n'
        '  - Outlines target problem scenarios and practical engineering goals.\n\n'
        '• KEY METHODOLOGIES & FORMULATIONS\n'
        '  - Formulates quantitative models, governing equations, and step-by-step algorithms.\n'
        '  - Details input parameters, execution steps, and internal state transitions.\n'
        '  - Provides analytical derivations and formal proofs for baseline conditions.\n\n'
        '• NOTABLE SUBTOPICS & MECHANISMS\n'
        '  - Detailed breakdown of key sub-components and structural system architecture.\n'
        '  - Highlights critical edge cases, boundary invariants, and system limits.\n'
        '  - Analyzes trade-offs between execution speed, memory footprint, and scalability.\n\n'
        '• EMPIRICAL FINDINGS & FIGURES\n'
        '  - Summarizes key experimental test cases, benchmark figures, and empirical datasets.\n'
        '  - Highlights observed performance trends and efficiency gains under test loads.\n'
        '  - Validates theoretical predictions against empirical measurement data.\n\n'
        '• CRITICAL TAKEAWAYS & BEST PRACTICES\n'
        '  - Takeaway 1: Validate structural invariants and boundary conditions prior to execution.\n'
        '  - Takeaway 2: Optimize bottleneck sub-modules according to performance trade-off models.\n'
        '  - Takeaway 3: Apply recommended implementation patterns for maximum system reliability.';

    _currentFlashCardIndex = 0;
    _isCardFlipped = false;
    _flashCardMasteredCount = 0;
    _currentQuizIndex = 0;
    _selectedOptionIndex = null;
    _quizSubmitted = false;
    _quizScore = 0;
    _isRefreshing = false;
  }

  void _parseIncomingAiResponse(String text) {
    setState(() => _isRefreshing = false);

    // Check if AI text contains multiple choice quiz questions
    if (text.contains('?') && (text.contains('A)') || text.contains('A.') || text.contains('1.'))) {
      final parsedQuizzes = _tryParseAiQuizzes(text);
      if (parsedQuizzes.isNotEmpty) {
        setState(() {
          _quizzes = parsedQuizzes;
          _currentQuizIndex = 0;
          _selectedOptionIndex = null;
          _quizSubmitted = false;
          _quizScore = 0;
        });
        return;
      }
    }

    // Check if AI text contains Flashcards (Q: / A:)
    if (text.contains('Q:') && text.contains('A:')) {
      final parsedCards = _tryParseAiFlashcards(text);
      if (parsedCards.isNotEmpty) {
        setState(() {
          _flashCards = parsedCards;
          _currentFlashCardIndex = 0;
          _isCardFlipped = false;
          _flashCardMasteredCount = 0;
        });
        return;
      }
    }

    // Check if AI text contains Concept definitions
    if (_activeTab == StudyTab.concepts || text.contains('•') || text.contains(':')) {
      final parsedConcepts = _tryParseAiConcepts(text);
      if (parsedConcepts.isNotEmpty) {
        setState(() {
          _concepts = parsedConcepts;
        });
        if (_activeTab == StudyTab.concepts) return;
      }
    }

    // Update study text or summary if active tab is Page Summary or Study Cards
    if (_activeTab == StudyTab.pageSummary) {
      setState(() {
        _pageSummaryText = text;
      });
    } else if (_activeTab == StudyTab.studyCards) {
      setState(() {
        _studyCardsText = text;
      });
    }
  }

  List<Map<String, dynamic>> _tryParseAiQuizzes(String text) {
    final List<Map<String, dynamic>> result = [];
    final lines = text.split('\n');
    String? currentQ;
    List<String> options = [];
    int correctIndex = 0;
    String explanation = 'Detailed solution derived from document text.';

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith(RegExp(r'^(Question|\d+[\.:\)])', caseSensitive: false))) {
        if (currentQ != null && options.length >= 2) {
          result.add({
            'question': currentQ,
            'options': List<String>.from(options),
            'correctIndex': correctIndex,
            'explanation': explanation,
          });
          options = [];
          correctIndex = 0;
        }
        currentQ = trimmed.replaceFirst(RegExp(r'^(Question|\d+[\.:\)])\s*'), '');
      } else if (trimmed.startsWith(RegExp(r'^[A-D][\)\.]\s*', caseSensitive: false))) {
        final optText = trimmed.replaceFirst(RegExp(r'^[A-D][\)\.]\s*', caseSensitive: false), '');
        if (trimmed.toLowerCase().contains('(correct)') || trimmed.toLowerCase().contains('*')) {
          correctIndex = options.length;
        }
        options.add(optText.replaceAll('*', '').replaceAll('(correct)', '').trim());
      } else if (trimmed.toLowerCase().startsWith('explanation:') || trimmed.toLowerCase().startsWith('solution:')) {
        explanation = trimmed.replaceFirst(RegExp(r'^(Explanation|Solution):\s*', caseSensitive: false), '');
      }
    }

    if (currentQ != null && options.length >= 2) {
      result.add({
        'question': currentQ,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      });
    }

    return result;
  }

  List<Map<String, dynamic>> _tryParseAiFlashcards(String text) {
    final List<Map<String, dynamic>> result = [];
    final blocks = text.split(RegExp(r'\n(?=Q:|Question:)'));
    final topic = _cleanTitle(widget.documentContext?.title ?? 'Document Subtopic');
    for (var block in blocks) {
      final lines = block.split('\n');
      String? q;
      String? a;
      for (var l in lines) {
        final tr = l.trim();
        if (tr.startsWith(RegExp(r'^(Q:|Question:)', caseSensitive: false))) {
          q = tr.replaceFirst(RegExp(r'^(Q:|Question:)\s*', caseSensitive: false), '');
        } else if (tr.startsWith(RegExp(r'^(A:|Answer:)', caseSensitive: false))) {
          a = tr.replaceFirst(RegExp(r'^(A:|Answer:)\s*', caseSensitive: false), '');
        }
      }
      if (q != null && a != null) {
        result.add({
          'question': q,
          'answer': a,
          'category': topic,
        });
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _tryParseAiConcepts(String text) {
    final List<Map<String, dynamic>> result = [];
    final lines = text.split('\n');
    final topic = _cleanTitle(widget.documentContext?.title ?? 'Document Topic');
    for (var l in lines) {
      final tr = l.trim();
      if (tr.startsWith('•') || tr.startsWith('-') || tr.startsWith(RegExp(r'^\d+\.'))) {
        final clean = tr.replaceFirst(RegExp(r'^[\•\-\d+\.]\s*'), '');
        final parts = clean.split(':');
        if (parts.length >= 2) {
          final conceptTitle = parts[0].trim();
          final rest = parts.sublist(1).join(':').trim();

          String explanation = rest;
          String application = 'Applied to design, evaluate, and optimize $conceptTitle mechanisms in $topic.';
          String takeaway = 'Key Rule: Maintain structural invariants and verify quantitative bounds for $conceptTitle.';

          if (rest.contains('|')) {
            final segments = rest.split('|');
            explanation = segments[0].trim();
            for (var seg in segments.sublist(1)) {
              final s = seg.trim();
              if (s.toLowerCase().startsWith('application:')) {
                application = s.replaceFirst(RegExp(r'^application:\s*', caseSensitive: false), '');
              } else if (s.toLowerCase().startsWith('takeaway:')) {
                takeaway = s.replaceFirst(RegExp(r'^takeaway:\s*', caseSensitive: false), '');
              }
            }
          }

          result.add({
            'title': conceptTitle,
            'subtitle': 'Subtopic Concept ${result.length + 1}',
            'explanation': explanation,
            'application': application,
            'takeaway': takeaway,
          });
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    _qaController.dispose();
    _specificationsController.dispose();
    _pageRangeController.dispose();
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt', 'md', 'docx'],
      allowMultiple: true,
      dialogTitle: 'Add Documents or Images to Study Context',
    );
    if (result == null) return;

    for (final file in result.files) {
      if (file.path != null) {
        final ext = file.extension?.toLowerCase() ?? '';
        final isImg = ['png', 'jpg', 'jpeg', 'webp'].contains(ext);
        setState(() {
          _attachmentPaths.add(file.path!);
          _attachmentNames.add(file.name);
          _attachmentIsImage.add(isImg);
        });
        if (ext == 'pdf') {
          _mergedPdfNames.add(file.name);
          _mergedPdfPaths.add(file.path!);
        }
      }
    }

    if (_attachmentPaths.isNotEmpty && _contextScope == StudyContextScope.activeTab) {
      setState(() => _contextScope = StudyContextScope.customMerged);
    }
  }

  void _sendStudyPrompt(String prompt) {
    if (widget.documentContext == null) return;

    final bool providerReady = widget.aiState.chat.providerReady &&
        widget.aiState.chat.selectedProviderId != null;

    if (!providerReady) {
      setState(() {
        _generateMaterialForCurrentDocument();
        _flashCards.shuffle();
        _quizzes.shuffle();
        _concepts.shuffle();
        _isRefreshing = false;
      });
      return;
    }

    setState(() => _isRefreshing = true);

    final StringBuffer buffer = StringBuffer();

    // 1. Difficulty Level & Page Range
    buffer.writeln('[TARGET DIFFICULTY LEVEL: $_difficultyLevel]');
    final pageRange = _pageRangeController.text.trim();
    if (pageRange.isNotEmpty) {
      buffer.writeln('[TARGET PAGE RANGE: $pageRange]');
    }

    // 2. User specifications
    final specs = _specificationsController.text.trim();
    if (specs.isNotEmpty) {
      buffer.writeln('[USER SPECIFICATIONS: "$specs"]');
    }

    // 3. Attachments
    if (_attachmentNames.isNotEmpty) {
      buffer.writeln('[MANUAL ATTACHMENTS & ASSETS: ${_attachmentNames.join(', ')}]');
    }

    // 4. Scope handling
    if (_contextScope == StudyContextScope.allOpenTabs) {
      final workspaceState = ref.read(workspaceNotifierProvider).value;
      final openTabs = workspaceState?.session.tabs ?? [];
      final tabTitles = openTabs.map((t) => _cleanTitle(t.title)).join(', ');
      buffer.writeln('[STUDY CONTEXT SCOPE: ALL OPEN WORKSPACE PDFS (${openTabs.length} PDFs: $tabTitles)]');
    } else if (_contextScope == StudyContextScope.customMerged && _mergedPdfNames.isNotEmpty) {
      final mergedNames = _mergedPdfNames.map(_cleanTitle).join(', ');
      buffer.writeln('[STUDY CONTEXT SCOPE: MERGED PDF POOL (${_mergedPdfNames.length} Merged PDFs: $mergedNames)]');
    }

    // 5. Anti-generic quality instructions
    final docTitle = _cleanTitle(widget.documentContext?.title ?? 'Document');
    buffer.writeln('[QUALITY DIRECTIVES: Include AT MOST ONE high-level generic question per generation (e.g. "What is the overall goal of $docTitle?"). All remaining 9 items MUST be specific, technical, subtopic-focused questions on concrete theorems, algorithms, formulas, and definitions. Infer related analytical questions to expand understanding.]');

    buffer.writeln(prompt);

    ref.read(aiNotifierProvider.notifier).sendPrompt(
      buffer.toString(),
      widget.documentContext!,
    );
  }

  void _refreshStudyModeContent() {
    final docTitle = _cleanTitle(widget.documentContext?.title ?? 'Active Document');
    final String pageRangeStr = _pageRangeController.text.trim().isNotEmpty ? 'pages ${_pageRangeController.text.trim()}' : 'the document';

    switch (_activeTab) {
      case StudyTab.quizzes:
        _sendStudyPrompt(
          'Generate 10 comprehensive multiple-choice quiz questions based on $pageRangeStr of "$docTitle" at $_difficultyLevel difficulty. '
          'RULE: Include AT MOST 1 generic high-level overview question. The remaining 9 questions MUST focus strictly on specific subtopics, formulas, definitions, mechanisms, and edge cases. '
          'Each question must have 4 options (A, B, C, D), indicate the correct option, and provide a detailed step-by-step solution.',
        );
        break;
      case StudyTab.flashCards:
        _sendStudyPrompt(
          'Generate 10 interactive Q&A flashcards based on $pageRangeStr of "$docTitle" at $_difficultyLevel difficulty. '
          'RULE: Include AT MOST 1 generic high-level overview question. The remaining 9 flashcards MUST test specific technical subtopics, mathematical equations, algorithms, definitions, and edge cases. Format each card with Q: and A: on separate lines.',
        );
        break;
      case StudyTab.concepts:
        _sendStudyPrompt(
          'Extract, name, and explain 10 core concepts and subtopics mentioned in $pageRangeStr of "$docTitle". '
          'Format each concept as: "• [Concept Name]: [Comprehensive 2-sentence explanation of concept and mechanism] | Application: [Real-world practical application or use case] | Takeaway: [Key formula, rule, or critical insight]".',
        );
        break;
      case StudyTab.pageSummary:
        _sendStudyPrompt(
          'Provide a detailed document summary of $pageRangeStr of "$docTitle" at $_difficultyLevel difficulty level. '
          'FORMAT REQUIREMENTS: Format strictly as concise, detailed short bullet points covering ALL things worth noting under 5 headings: '
          '• 1. Core Scope & Objectives (bullet points)\n'
          '• 2. Key Methodologies & Formulations (bullet points)\n'
          '• 3. Notable Subtopics & Mechanisms (bullet points)\n'
          '• 4. Empirical Findings & Figures (bullet points)\n'
          '• 5. Critical Takeaways & Best Practices (bullet points)',
        );
        break;
      case StudyTab.studyCards:
        _sendStudyPrompt(
          'Generate a master study guide card for "$docTitle" ($pageRangeStr) at $_difficultyLevel difficulty level with key formulas, core definitions, and structured revision points.',
        );
        break;
      case StudyTab.qaChat:
        _sendStudyPrompt(
          'Analyze $pageRangeStr of "$docTitle" and provide an executive study brief covering major subtopics, key theorems, and 5 suggested deep-dive questions to explore.',
        );
        break;
      default:
        _sendStudyPrompt(
          'Analyze $pageRangeStr of "$docTitle" and generate detailed structural insights for study mode.',
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      color: Colors.transparent,
      child: Column(
        children: <Widget>[
          // Header Bar
          _buildHeader(),

          // Scope & Search Specification Bar
          _buildControlToolbar(),

          // Glass Segmented Tab Switcher
          _buildNavTabs(),

          // AI Busy Progress Banner
          if (widget.aiState.chat.chatBusy || _isRefreshing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0x336366F1),
              child: Row(
                children: const [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA5B4FC)),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI analyzing PDF context & generating 10 study items...',
                      style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Main Animated Tab Workspace Area
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(widget.isFullScreen ? 18.0 : 10.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.02, 0.0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<StudyTab>(_activeTab),
                  child: _buildActiveTabContent(),
                ),
              ),
            ),
          ),
          if (ref.watch(offlineAudioBookServiceProvider).state != AudioBookState.idle)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: AudioBookPlayerBar(
                audioBookService: ref.watch(offlineAudioBookServiceProvider),
              ),
            ),
        ],
      ),
    );

    final glassContainer = ClipRRect(
      borderRadius: BorderRadius.circular(widget.isFullScreen ? 16 : 0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFA1E1E22),
            borderRadius: BorderRadius.circular(widget.isFullScreen ? 16 : 0),
            border: Border.all(
              color: const Color(0xFF3F3F46),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x88000000),
                blurRadius: widget.isFullScreen ? 25 : 10,
                spreadRadius: widget.isFullScreen ? 2 : 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: body,
        ),
      ),
    );

    final mainWidget = widget.isFullScreen
        ? Container(
            color: const Color(0xFF141416),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: glassContainer,
              ),
            ),
          )
        : glassContainer;

    if (widget.isFullScreen && widget.onToggleFullScreen != null) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): widget.onToggleFullScreen!,
        },
        child: Focus(
          autofocus: true,
          child: mainWidget,
        ),
      );
    }
    return mainWidget;
  }

  Widget _buildHeader() {
    final titleText = _cleanTitle(widget.documentContext?.title ?? 'Workspace PDF');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF27272A),
        border: Border(bottom: BorderSide(color: Color(0xFF3F3F46))),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF3F3F46),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF52525B)),
            ),
            child: const QaMergedIcon(size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Study Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F3F46),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF52525B), width: 0.8),
                      ),
                      child: const Text(
                        'RAG ENGINE',
                        style: TextStyle(color: Color(0xFFE4E4E7), fontSize: 8.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  titleText,
                  style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10.5, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Privacy-First Data Masking (Smart Redact)',
            child: IconButton(
              icon: const Icon(LucideIcons.shieldAlert, size: 15, color: Color(0xFFA1A1AA)),
              onPressed: () {
                final documentText = _pageSummaryText;
                showDialog(
                  context: context,
                  builder: (ctx) => RedactionDialog(
                    documentText: documentText,
                    redactionService: ref.read(smartRedactionServiceProvider),
                  ),
                );
              },
            ),
          ),
          Tooltip(
            message: 'Offline Audio-Book Mode',
            child: IconButton(
              icon: const Icon(LucideIcons.headphones, size: 15, color: Color(0xFFA1A1AA)),
              onPressed: () async {
                final audioBook = ref.read(offlineAudioBookServiceProvider);
                final doc = widget.documentContext;
                if (doc != null && doc.filePath.isNotEmpty) {
                  await audioBook.loadPdfDocument(doc.filePath, _cleanTitle(doc.title));
                } else if (_pageSummaryText.isNotEmpty) {
                  audioBook.loadBook([_pageSummaryText], title: 'Study Notes');
                }
                audioBook.play();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Audiobook reading "${audioBook.bookTitle}"!'), duration: const Duration(seconds: 2)),
                );
              },
            ),
          ),
          Tooltip(
            message: 'Refresh Study Mode & generate 10 new items',
            child: IconButton(
              icon: const Icon(LucideIcons.refreshCw, size: 15, color: Color(0xFFA1A1AA)),
              onPressed: _refreshStudyModeContent,
            ),
          ),
          Tooltip(
            message: 'Add document or image asset',
            child: IconButton(
              icon: const Icon(LucideIcons.plus, size: 15, color: Color(0xFFA1A1AA)),
              onPressed: _pickAttachments,
            ),
          ),
          if (widget.isFullScreen)
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF27272A),
                foregroundColor: const Color(0xFFFAFAFA),
                side: const BorderSide(color: Color(0xFF3F3F46)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(LucideIcons.x, size: 14, color: Color(0xFFA1A1AA)),
              label: const Text('Exit Full Screen', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: widget.onToggleFullScreen,
            )
          else if (widget.onToggleFullScreen != null)
            Tooltip(
              message: 'Full Screen Workspace Mode',
              child: IconButton(
                icon: const Icon(LucideIcons.maximize2, size: 15, color: Colors.white70),
                onPressed: widget.onToggleFullScreen,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0x331E293B),
        border: Border(bottom: BorderSide(color: Color(0x15FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Scope Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                const Text('Scope: ', style: TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.bold)),
                _scopeChip(StudyContextScope.activeTab, '📄 Active PDF'),
                const SizedBox(width: 4),
                _scopeChip(StudyContextScope.allOpenTabs, '📚 All Open PDFs'),
                if (_mergedPdfNames.isNotEmpty || _attachmentNames.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 4),
                  _scopeChip(StudyContextScope.customMerged, '🧩 Merged (${_attachmentNames.length + _mergedPdfNames.length})'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Difficulty & Page Range Controls
          Row(
            children: <Widget>[
              const Text('Difficulty: ', style: TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              _difficultyChip('Easy'),
              const SizedBox(width: 2),
              _difficultyChip('Medium'),
              const SizedBox(width: 2),
              _difficultyChip('Hard'),
              const SizedBox(width: 2),
              _difficultyChip('Master'),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _pageRangeController,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Pages (e.g. 1-10)',
                      hintStyle: const TextStyle(fontSize: 10, color: Colors.white38),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0x440F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0x3364748B))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_attachmentNames.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: List.generate(_attachmentNames.length, (index) {
                final name = _attachmentNames[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x33334155),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0x4464748B)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(LucideIcons.fileText, size: 10, color: Color(0xFFA5B4FC)),
                      const SizedBox(width: 4),
                      Text(name, style: const TextStyle(fontSize: 9.5, color: Colors.white)),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _attachmentNames.removeAt(index);
                            _attachmentPaths.removeAt(index);
                            _attachmentIsImage.removeAt(index);
                          });
                        },
                        child: const Icon(LucideIcons.x, size: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeChip(StudyContextScope scope, String label) {
    final bool active = _contextScope == scope;
    return Tooltip(
      message: 'Set study scope to $label',
      child: InkWell(
        onTap: () => setState(() => _contextScope = scope),
        borderRadius: BorderRadius.circular(5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: active ? const Color(0xFF71717A) : const Color(0xFF3F3F46)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? const Color(0xFFFAFAFA) : const Color(0xFFA1A1AA),
            ),
          ),
        ),
      ),
    );
  }

  Widget _difficultyChip(String level) {
    final bool active = _difficultyLevel == level;
    return InkWell(
      onTap: () => setState(() => _difficultyLevel = level),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? const Color(0xFF71717A) : const Color(0xFF3F3F46)),
        ),
        child: Text(
          level,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? const Color(0xFFFAFAFA) : const Color(0xFFA1A1AA),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTabs() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E22),
        border: Border(bottom: BorderSide(color: Color(0xFF3F3F46))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _tabChip(StudyTab.qaChat, 'Q&A Chat', LucideIcons.messageSquare),
          _tabChip(StudyTab.quizzes, '10 Quizzes', LucideIcons.helpCircle),
          _tabChip(StudyTab.flashCards, '10 Flash Cards', LucideIcons.layers),
          _tabChip(StudyTab.concepts, '10 Concepts', LucideIcons.lightbulb),
          _tabChip(StudyTab.studyCards, 'Study Guide', LucideIcons.bookOpen),
          _tabChip(StudyTab.pageSummary, 'Summary', LucideIcons.fileText),
          _tabChip(StudyTab.audiobook, 'Audiobook', LucideIcons.headphones),
          _tabChip(StudyTab.bionic, 'Bionic Reading', LucideIcons.eye),
        ],
      ),
    );
  }

  Widget _tabChip(StudyTab tab, String label, IconData icon) {
    final bool active = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Tooltip(
        message: 'Switch to $label',
        child: InkWell(
          onTap: () => setState(() => _activeTab = tab),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active ? const Color(0xFF71717A) : const Color(0xFF3F3F46),
                width: active ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: active ? Colors.white : const Color(0xFFA1A1AA)),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? Colors.white : const Color(0xFFA1A1AA),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    return switch (_activeTab) {
      StudyTab.quizzes => _buildQuizzesView(),
      StudyTab.flashCards => _buildFlashCardsView(),
      StudyTab.concepts => _buildConceptsView(),
      StudyTab.studyCards => _buildStudyCardsView(),
      StudyTab.pageSummary => _buildPageSummaryView(),
      StudyTab.qaChat => _buildQaChatView(),
      StudyTab.audiobook => _buildAudiobookView(),
      StudyTab.bionic => _buildBionicView(),
    };
  }

  Widget _buildAudiobookView() {
    final audioBook = ref.watch(offlineAudioBookServiceProvider);
    final docTitle = audioBook.bookTitle.isNotEmpty
        ? audioBook.bookTitle
        : _cleanTitle(widget.documentContext?.title ?? 'Active PDF Document');

    final paragraphs = audioBook.currentParagraphs;
    final activeParIndex = audioBook.currentParagraphIndex;
    final isPlaying = audioBook.isPlaying;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3F3F46)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF27272A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFF3F3F46))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.headphones, size: 16, color: Color(0xFFA5B4FC)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Audiobook • $docTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPlaying ? const Color(0x3310B981) : const Color(0xFF3F3F46),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isPlaying ? const Color(0xFF10B981) : const Color(0xFF71717A)),
                      ),
                      child: Text(
                        isPlaying ? 'PLAYING' : 'PAUSED',
                        style: TextStyle(
                          color: isPlaying ? const Color(0xFF34D399) : const Color(0xFFA1A1AA),
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Reading Page ${audioBook.currentPageIndex + 1} of ${audioBook.totalPages} directly from open PDF document.',
                  style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10.5),
                ),
              ],
            ),
          ),

          // Controls Toolbar (Voice & Speed & Page Navigation)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF202024),
            child: Column(
              children: [
                Row(
                  children: [
                    // Voice Selector
                    const Icon(LucideIcons.user, size: 14, color: Color(0xFFA5B4FC)),
                    const SizedBox(width: 6),
                    const Text('Voice: ', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    PopupMenuButton<String>(
                      initialValue: audioBook.selectedVoice,
                      tooltip: 'Select Voice',
                      onSelected: (voice) => audioBook.setSelectedVoice(voice),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'Zira', child: Text('Microsoft Zira (Female - Clear)', style: TextStyle(fontSize: 11))),
                        PopupMenuItem(value: 'David', child: Text('Microsoft David (Male - Deep)', style: TextStyle(fontSize: 11))),
                        PopupMenuItem(value: 'Mark', child: Text('Microsoft Mark (Male - Warm)', style: TextStyle(fontSize: 11))),
                        PopupMenuItem(value: 'kitten_female_1', child: Text('Kitten Female (Neural)', style: TextStyle(fontSize: 11))),
                        PopupMenuItem(value: 'kitten_male_1', child: Text('Kitten Male (Neural)', style: TextStyle(fontSize: 11))),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27272A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF3F3F46)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              audioBook.selectedVoice.contains('Zira')
                                  ? 'Microsoft Zira (Female)'
                                  : audioBook.selectedVoice.contains('David')
                                      ? 'Microsoft David (Male)'
                                      : audioBook.selectedVoice.contains('Mark')
                                          ? 'Microsoft Mark (Male)'
                                          : audioBook.selectedVoice,
                              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            const Icon(LucideIcons.chevronDown, size: 12, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),

                    // Speed Selector
                    PopupMenuButton<double>(
                      initialValue: audioBook.playbackSpeed,
                      tooltip: 'Playback Speed',
                      onSelected: (speed) => audioBook.setPlaybackSpeed(speed),
                      itemBuilder: (context) => [0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                        return PopupMenuItem<double>(
                          value: s,
                          child: Text('${s}x Speed', style: const TextStyle(fontSize: 11)),
                        );
                      }).toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27272A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF3F3F46)),
                        ),
                        child: Text(
                          '${audioBook.playbackSpeed}x Speed',
                          style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Transport Controls Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.skipBack, size: 16, color: Colors.white70),
                      onPressed: () => audioBook.previousPage(),
                      tooltip: 'Previous Page',
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (isPlaying) {
                          audioBook.pause();
                        } else {
                          audioBook.play();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPlaying ? const Color(0xFFEF4444) : const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      icon: Icon(isPlaying ? LucideIcons.pause : LucideIcons.play, size: 16),
                      label: Text(isPlaying ? 'Pause Audiobook' : 'Play Audiobook', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(LucideIcons.skipForward, size: 16, color: Colors.white70),
                      onPressed: () => audioBook.nextPage(),
                      tooltip: 'Next Page',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF3F3F46)),

          // Scrollable PDF Text View with Live Paragraph Highlight (Karaoke Tracker)
          Expanded(
            child: paragraphs.isEmpty
                ? const Center(
                    child: Text('No PDF text extracted for this page.', style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: paragraphs.length,
                    itemBuilder: (context, index) {
                      final isCurrentLine = isPlaying && index == activeParIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCurrentLine ? const Color(0x336366F1) : const Color(0xFF202024),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCurrentLine ? const Color(0xFF818CF8) : const Color(0xFF27272A),
                            width: isCurrentLine ? 1.5 : 1.0,
                          ),
                          boxShadow: isCurrentLine
                              ? [
                                  const BoxShadow(
                                    color: Color(0x446366F1),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isCurrentLine)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.volume2, size: 10, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text('READING NOW', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            SelectableText(
                              paragraphs[index],
                              style: TextStyle(
                                color: isCurrentLine ? Colors.white : const Color(0xFFD4D4D8),
                                fontSize: 12,
                                fontWeight: isCurrentLine ? FontWeight.w600 : FontWeight.normal,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBionicView() {
    String sourceText = switch (_bionicSource) {
      'studyCards' => _studyCardsText,
      'concepts' => _concepts.map((c) => '• ${c['title']}: ${c['explanation']}\n  - Application: ${c['application']}\n  - Takeaway: ${c['takeaway']}').join('\n\n'),
      _ => _pageSummaryText,
    };

    if (sourceText.trim().isEmpty) {
      final docTitle = _cleanTitle(widget.documentContext?.title ?? 'Active Document');
      sourceText = '📌 $docTitle Study Notes\n\n'
          'Bionic Reading bolds the fixation letters of every word to guide your eyes smoothly through dense textbook material.\n'
          'Use the source buttons above or generate a Summary/Study Guide first to view Bionic Reading formatting!';
    }

    final spans = _generateBionicSpans(sourceText);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3F3F46)),
      ),
      child: Column(
        children: [
          // Bionic Header & Explanation Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF27272A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: Color(0xFF3F3F46))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.eye, size: 16, color: Color(0xFFA5B4FC)),
                    const SizedBox(width: 8),
                    const Text(
                      'Bionic Reading View',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    // TTS Audio Play Button
                    Tooltip(
                      message: 'Listen to text (Audiobook TTS)',
                      child: InkWell(
                        onTap: () {
                          if (sourceText.trim().isNotEmpty) {
                            final audioBook = ref.read(offlineAudioBookServiceProvider);
                            final docTitle = _cleanTitle(widget.documentContext?.title ?? 'Bionic Notes');
                            audioBook.loadBook([sourceText], title: '$docTitle (Bionic)');
                            audioBook.play();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Audiobook reading "$docTitle (Bionic)"!'), duration: const Duration(seconds: 2)),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x336366F1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0x666366F1)),
                          ),
                          child: const Row(
                            children: [
                              Icon(LucideIcons.volume2, size: 12, color: Color(0xFFA5B4FC)),
                              SizedBox(width: 4),
                              Text('Listen', style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Copy Plain Text Button
                    Tooltip(
                      message: 'Copy text',
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: sourceText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bionic text copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3F3F46),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(LucideIcons.copy, size: 12, color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '💡 Bionic Reading highlights initial fixation letters of words to guide your eyes through dense textbook material, boosting speed & focus.',
                  style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 10.5, height: 1.3),
                ),
              ],
            ),
          ),

          // Control Toolbar (Source & Fixation Intensity & Font Size)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF202024),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Source selector
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Source: ', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    _bionicSourceChip('Summary', 'summary'),
                    const SizedBox(width: 4),
                    _bionicSourceChip('Study Guide', 'studyCards'),
                    const SizedBox(width: 4),
                    _bionicSourceChip('Concepts', 'concepts'),
                  ],
                ),
                // Fixation Intensity
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Fixation: ', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    _bionicFixationChip('Low', 0.30),
                    const SizedBox(width: 4),
                    _bionicFixationChip('Med', 0.45),
                    const SizedBox(width: 4),
                    _bionicFixationChip('High', 0.60),
                  ],
                ),
                // Font Size Adjuster
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Size: ', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    InkWell(
                      onTap: () {
                        if (_bionicFontSize > 10.0) {
                          setState(() => _bionicFontSize -= 1.0);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF27272A), borderRadius: BorderRadius.circular(4)),
                        child: const Text('A-', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('${_bionicFontSize.toInt()}px', style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 10.5, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        if (_bionicFontSize < 20.0) {
                          setState(() => _bionicFontSize += 1.0);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF27272A), borderRadius: BorderRadius.circular(4)),
                        child: const Text('A+', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF3F3F46)),

          // Scrollable Bionic Content Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText.rich(
                TextSpan(children: spans),
                style: const TextStyle(height: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _generateBionicSpans(String text) {
    if (text.isEmpty) {
      return [
        TextSpan(
          text: 'No text available for Bionic Reading.',
          style: TextStyle(color: Colors.white54, fontSize: _bionicFontSize),
        ),
      ];
    }

    final List<InlineSpan> spans = <InlineSpan>[];
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) {
        spans.add(TextSpan(text: '\n\n', style: TextStyle(fontSize: _bionicFontSize)));
        continue;
      }

      final regExp = RegExp(r'(\w+)|([^\w]+)');
      final matches = regExp.allMatches(line);

      for (final match in matches) {
        final word = match.group(1);
        final nonWord = match.group(2);

        if (word != null) {
          if (word.length <= 1) {
            spans.add(TextSpan(
              text: word,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: _bionicFontSize,
                letterSpacing: 0.3,
              ),
            ));
          } else {
            final boldLen = (word.length * _bionicFixationRatio).ceil().clamp(1, word.length);
            final boldPart = word.substring(0, boldLen);
            final restPart = word.substring(boldLen);

            spans.add(TextSpan(
              text: boldPart,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: _bionicFontSize,
                letterSpacing: 0.3,
              ),
            ));

            if (restPart.isNotEmpty) {
              spans.add(TextSpan(
                text: restPart,
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFD4D4D8),
                  fontSize: _bionicFontSize,
                  letterSpacing: 0.2,
                ),
              ));
            }
          }
        } else if (nonWord != null) {
          spans.add(TextSpan(
            text: nonWord,
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: const Color(0xFFA1A1AA),
              fontSize: _bionicFontSize,
            ),
          ));
        }
      }

      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: TextStyle(fontSize: _bionicFontSize)));
      }
    }

    return spans;
  }

  Widget _bionicSourceChip(String label, String value) {
    final active = _bionicSource == value;
    return InkWell(
      onTap: () => setState(() => _bionicSource = value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6366F1) : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFA1A1AA),
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _bionicFixationChip(String label, double ratio) {
    final active = (_bionicFixationRatio - ratio).abs() < 0.05;
    return InkWell(
      onTap: () => setState(() => _bionicFixationRatio = ratio),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF10B981) : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFFA1A1AA),
            fontSize: 10,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // 1. Quizzes View
  Widget _buildQuizzesView() {
    if (_quizzes.isEmpty) {
      return const Center(
        child: Text('No quiz questions generated yet.', style: TextStyle(color: Colors.white70)),
      );
    }
    final quiz = _quizzes[_currentQuizIndex % _quizzes.length];
    final options = (quiz['options'] as List).map((e) => e.toString()).toList();
    final correctIndex = (quiz['correctIndex'] as int?) ?? 0;
    final progressRatio = ((_currentQuizIndex % _quizzes.length) + 1) / _quizzes.length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header Action Strip
          Row(
            children: [
              Text(
                'Question ${(_currentQuizIndex % _quizzes.length) + 1} of ${_quizzes.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF27272A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3F3F46)),
                ),
                child: Text('Score: $_quizScore / ${_quizzes.length}', style: const TextStyle(color: Color(0xFFFAFAFA), fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              Tooltip(
                message: 'Regenerate 10 New Quizzes via AI',
                child: IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFFA1A1AA)),
                  onPressed: _refreshStudyModeContent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: 5,
              backgroundColor: const Color(0xFF27272A),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF71717A)),
            ),
          ),
          const SizedBox(height: 12),

          // Question Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF242427),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3F3F46), width: 1.0),
            ),
            child: Text(
              quiz['question'] as String,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),

          // Options List
          ...List.generate(options.length, (index) {
            final optionLetter = String.fromCharCode(65 + index);
            final optionText = options[index];
            final isSelected = _selectedOptionIndex == index;
            final isCorrect = index == correctIndex;

            Color bgColor = const Color(0xFF27272A);
            Color borderColor = const Color(0xFF3F3F46);
            Color textColor = Colors.white;

            if (_quizSubmitted) {
              if (isCorrect) {
                bgColor = const Color(0xFF143828);
                borderColor = const Color(0xFF059669);
                textColor = const Color(0xFF6EE7B7);
              } else if (isSelected && !isCorrect) {
                bgColor = const Color(0xFF381414);
                borderColor = const Color(0xFFDC2626);
                textColor = const Color(0xFFFCA5A5);
              }
            } else if (isSelected) {
              borderColor = const Color(0xFF71717A);
              bgColor = const Color(0xFF3F3F46);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _quizSubmitted ? null : () => setState(() => _selectedOptionIndex = index),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: isSelected || (_quizSubmitted && isCorrect) ? 1.4 : 1.0),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: borderColor.withValues(alpha: 0.25)),
                        child: Text(optionLetter, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(optionText, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      if (_quizSubmitted && isCorrect) const Icon(LucideIcons.checkCircle2, size: 16, color: Color(0xFF059669)),
                      if (_quizSubmitted && isSelected && !isCorrect) const Icon(LucideIcons.xCircle, size: 16, color: Color(0xFFDC2626)),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),

          // Submit & Explanation Action
          if (!_quizSubmitted)
            FilledButton.icon(
              onPressed: _selectedOptionIndex == null
                  ? null
                  : () {
                      setState(() {
                        _quizSubmitted = true;
                        if (_selectedOptionIndex == correctIndex) {
                          _quizScore++;
                        }
                      });
                    },
              icon: const Icon(LucideIcons.checkCircle, size: 14),
              label: const Text('Submit Answer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3F3F46),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )
          else ...<Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF27272A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3F3F46)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _selectedOptionIndex == correctIndex ? 'Correct Explanation:' : 'Solution Explanation:',
                    style: const TextStyle(color: Color(0xFFE4E4E7), fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text((quiz['explanation'] as String?) ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _currentQuizIndex = (_currentQuizIndex + 1) % _quizzes.length;
                  _selectedOptionIndex = null;
                  _quizSubmitted = false;
                });
              },
              icon: const Icon(LucideIcons.arrowRight, size: 14),
              label: Text((_currentQuizIndex % _quizzes.length) + 1 < _quizzes.length ? 'Next Question' : 'Restart Quiz', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF3F3F46)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 2. Flash Cards View
  Widget _buildFlashCardsView() {
    if (_flashCards.isEmpty) {
      return const Center(
        child: Text('No flashcards available.', style: TextStyle(color: Colors.white70)),
      );
    }
    final card = _flashCards[_currentFlashCardIndex % _flashCards.length];
    final masteredRatio = _flashCardMasteredCount / _flashCards.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Action Strip
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('Card ${(_currentFlashCardIndex % _flashCards.length) + 1} of ${_flashCards.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF27272A), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF3F3F46))),
              child: Text('Mastered: $_flashCardMasteredCount / ${_flashCards.length}', style: const TextStyle(color: Color(0xFFFAFAFA), fontSize: 10.5, fontWeight: FontWeight.bold)),
            ),
            Tooltip(
              message: 'Regenerate 10 New Flash Cards',
              child: IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFFA1A1AA)),
                onPressed: _refreshStudyModeContent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: masteredRatio,
            minHeight: 5,
            backgroundColor: const Color(0xFF27272A),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF71717A)),
          ),
        ),
        const SizedBox(height: 10),

        // 3D Flip Card
        Expanded(
          child: _FlashCard3DWidget(
            question: (card['question'] as String?) ?? 'Question',
            answer: (card['answer'] as String?) ?? 'Answer',
            category: (card['category'] as String?) ?? _cleanTitle(widget.documentContext?.title ?? 'Document'),
            isFlipped: _isCardFlipped,
            onTap: () => setState(() => _isCardFlipped = !_isCardFlipped),
          ),
        ),
        const SizedBox(height: 10),

        // Action Buttons
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _currentFlashCardIndex = (_currentFlashCardIndex - 1 + _flashCards.length) % _flashCards.length;
                    _isCardFlipped = false;
                  });
                },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF3F3F46)), padding: const EdgeInsets.symmetric(vertical: 10)),
                child: const Text('Prev', style: TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _flashCardMasteredCount = math.min(_flashCards.length, _flashCardMasteredCount + 1);
                    _currentFlashCardIndex = (_currentFlashCardIndex + 1) % _flashCards.length;
                    _isCardFlipped = false;
                  });
                },
                icon: const Icon(LucideIcons.check, size: 14),
                label: const Text('Got It', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3F3F46), padding: const EdgeInsets.symmetric(vertical: 10)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _currentFlashCardIndex = (_currentFlashCardIndex + 1) % _flashCards.length;
                    _isCardFlipped = false;
                  });
                },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF3F3F46)), padding: const EdgeInsets.symmetric(vertical: 10)),
                child: const Text('Next', style: TextStyle(fontSize: 11, color: Colors.white)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 3. Concepts View
  Widget _buildConceptsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: [
            const Text('10 Core Document Concepts', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            Tooltip(
              message: 'Extract 10 Named Core Concepts from Document',
              child: IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFFF59E0B)),
                onPressed: _refreshStudyModeContent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '💡 Tap card or view tabs to switch between Definition, Practical Application, and Key Takeaways.',
          style: TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: List.generate(_concepts.length, (index) {
                final c = _concepts[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ConceptCard(
                    title: (c['title'] as String?) ?? 'Concept',
                    subtitle: (c['subtitle'] as String?) ?? 'Subtopic Concept ${index + 1}',
                    explanation: (c['explanation'] as String?) ?? '',
                    application: (c['application'] as String?) ?? 'Applied directly to analyze, evaluate, and optimize systems.',
                    takeaway: (c['takeaway'] as String?) ?? 'Key Rule: Validate invariants and verify quantitative bounds.',
                    onAskDeepDive: (conceptTitle) {
                      _sendStudyPrompt(
                        'Provide an in-depth technical breakdown of the core concept "$conceptTitle" in "${_cleanTitle(widget.documentContext?.title ?? 'Document')}". '
                        'Explain its mathematical foundation, step-by-step algorithms, practical implementation scenarios, and key edge case constraints.',
                      );
                    },
                  ),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  // 4. Study Cards View
  Widget _buildStudyCardsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: [
            const Text('Topic Study Guide Card', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            Tooltip(
              message: 'Regenerate Study Guide Card',
              child: IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFFA1A1AA)),
                onPressed: _refreshStudyModeContent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF242427),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3F3F46)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _studyCardsText,
                style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 5. Page Summary View
  Widget _buildPageSummaryView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: [
            const Text('Detailed Bulleted Summary', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            Tooltip(
              message: 'Read Summary Aloud via KittenTTS',
              child: IconButton(
                icon: const Icon(LucideIcons.volume2, size: 14, color: Color(0xFFA1A1AA)),
                onPressed: () {
                  ref.read(kittenTtsServiceProvider).speak(_pageSummaryText);
                },
              ),
            ),
            Tooltip(
              message: 'Copy Summary Bullet Points to Clipboard',
              child: IconButton(
                icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white70),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _pageSummaryText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Detailed summary copied to clipboard!'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ),
            Tooltip(
              message: 'Regenerate Detailed Short-Points Summary',
              child: IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFFA1A1AA)),
                onPressed: _refreshStudyModeContent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF242427),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3F3F46)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _pageSummaryText,
                style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.55),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 6. Q&A Chat View with Audio-to-Audio & KittenTTS Voice Interaction
  Widget _buildQaChatView() {
    final titleText = _cleanTitle(widget.documentContext?.title ?? 'Document');
    final audioService = ref.watch(audioToAudioServiceProvider);
    final ttsService = ref.watch(kittenTtsServiceProvider);
    final isListening = audioService.state == AudioInteractionState.listening;

    return Column(
      children: <Widget>[
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF242427),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3F3F46)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(LucideIcons.sparkles, size: 14, color: Color(0xFFE4E4E7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Semantic Q&A Engine for $titleText',
                          style: const TextStyle(color: Color(0xFFFAFAFA), fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Ask specific subtopic questions to expand deep understanding.', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const Divider(height: 16, color: Color(0xFF3F3F46)),
                  ...widget.aiState.chat.messages.map((m) {
                    final isUser = m.isUser;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          if (!isUser) ...[
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(color: Color(0xFF3F3F46), shape: BoxShape.circle),
                              child: const Icon(LucideIcons.bot, size: 11, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF3F3F46) : const Color(0xFF27272A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(m.text, style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.4)),
                            ),
                          ),
                          if (!isUser) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(LucideIcons.volume2, size: 12, color: Color(0xFFA1A1AA)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Listen via KittenTTS',
                              onPressed: () => ttsService.speak(m.text),
                            ),
                          ],
                          if (isUser) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(color: Color(0xFF52525B), shape: BoxShape.circle),
                              child: const Icon(LucideIcons.user, size: 11, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        if (audioService.state != AudioInteractionState.idle) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isListening ? const Color(0xFF381414) : const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isListening ? const Color(0xFFDC2626) : const Color(0xFF3F3F46)),
            ),
            child: Row(
              children: [
                Icon(
                  isListening ? LucideIcons.mic : LucideIcons.loader2,
                  size: 13,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    audioService.state == AudioInteractionState.listening
                        ? '🎙️ Listening to mic... Click mic again to send.'
                        : audioService.state == AudioInteractionState.transcribing
                            ? '✍️ Transcribing speech to text...'
                            : audioService.state == AudioInteractionState.thinking
                                ? '🧠 Local AI is reasoning...'
                                : audioService.state == AudioInteractionState.speaking
                                    ? '🔊 KittenTTS speaking AI response...'
                                    : '⚠️ Voice error: ${audioService.lastError ?? "Unknown"}',
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _qaController,
                style: const TextStyle(fontSize: 11.5, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ask a specific study question...',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF27272A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3F3F46))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty) {
                    _sendStudyPrompt(text.trim());
                    _qaController.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: isListening ? 'Stop & Send Voice Input' : 'Start Audio-to-Audio Voice Chat',
              child: IconButton.filled(
                onPressed: () async {
                  if (isListening) {
                    await audioService.stopAndProcess((prompt) async {
                      _sendStudyPrompt(prompt);
                      final messages = widget.aiState.chat.messages;
                      return messages.isEmpty ? 'I processed your voice prompt.' : messages.last.text;
                    });
                  } else {
                    await audioService.startListening();
                  }
                },
                icon: Icon(isListening ? LucideIcons.micOff : LucideIcons.mic, size: 14),
                style: IconButton.styleFrom(
                  backgroundColor: isListening ? const Color(0xFFDC2626) : const Color(0xFF3F3F46),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Local Mathematical Formula Parsing (LaTeX-OCR)',
              child: IconButton.filled(
                onPressed: () => _showLatexOcrDialog(context),
                icon: const Icon(LucideIcons.functionSquare, size: 14),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF3F3F46),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: () {
                if (_qaController.text.trim().isNotEmpty) {
                  _sendStudyPrompt(_qaController.text.trim());
                  _qaController.clear();
                }
              },
              icon: const Icon(LucideIcons.send, size: 14),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF52525B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showLatexOcrDialog(BuildContext context) {
    final textController = TextEditingController(text: 'int 0 to infinity alpha * x^2 dx');
    String latexResult = ref.read(latexOcrServiceProvider).parseTextToLatex(textController.text);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0x3364748B))),
            title: const Row(
              children: [
                Icon(LucideIcons.functionSquare, size: 18, color: Color(0xFF38BDF8)),
                SizedBox(width: 8),
                Text('Local LaTeX Math OCR & Formula Parser', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter mathematical expression or OCR tokens:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: textController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'e.g. sqrt(x + 1) / (y - 2) or int 0 to inf alpha * x^2 dx',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      filled: true,
                      fillColor: const Color(0x441E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0x3364748B))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (val) {
                      setState(() {
                        latexResult = ref.read(latexOcrServiceProvider).parseTextToLatex(val);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Generated LaTeX Code:', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x66020617),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x2238BDF8)),
                    ),
                    child: SelectableText(
                      latexResult,
                      style: const TextStyle(color: Color(0xFF7DD3FC), fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (latexResult.trim().isNotEmpty) {
                    setState(() {
                      _qaController.text = '${_qaController.text} $latexResult'.trim();
                    });
                  }
                  Navigator.of(ctx).pop();
                },
                icon: const Icon(LucideIcons.plus, size: 14),
                label: const Text('Insert into Q&A Chat Prompt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConceptCard extends StatefulWidget {
  const _ConceptCard({
    required this.title,
    required this.subtitle,
    required this.explanation,
    required this.application,
    required this.takeaway,
    this.onAskDeepDive,
  });

  final String title;
  final String subtitle;
  final String explanation;
  final String application;
  final String takeaway;
  final ValueChanged<String>? onAskDeepDive;

  @override
  State<_ConceptCard> createState() => _ConceptCardState();
}

class _ConceptCardState extends State<_ConceptCard> {
  int _activeViewIndex = 0; // 0: Definition, 1: Application, 2: Takeaway

  @override
  Widget build(BuildContext context) {
    String currentText = widget.explanation;
    IconData currentIcon = LucideIcons.lightbulb;
    Color activeColor = const Color(0xFFFAFAFA);
    String modeLabel = 'Core Definition & Mechanism';

    if (_activeViewIndex == 1) {
      currentText = widget.application;
      currentIcon = LucideIcons.zap;
      activeColor = const Color(0xFFE4E4E7);
      modeLabel = 'Practical Real-World Application';
    } else if (_activeViewIndex == 2) {
      currentText = widget.takeaway;
      currentIcon = LucideIcons.target;
      activeColor = const Color(0xFFD4D4D8);
      modeLabel = 'Key Rule & Structural Invariant';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242427),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3F3F46), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(currentIcon, size: 14, color: activeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onAskDeepDive != null)
                Tooltip(
                  message: 'Ask AI Assistant to Deep Dive on "${widget.title}"',
                  child: InkWell(
                    onTap: () => widget.onAskDeepDive!(widget.title),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F3F46),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF52525B)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.sparkles, size: 10, color: Color(0xFFFAFAFA)),
                          SizedBox(width: 3),
                          Text('Deep Dive', style: TextStyle(color: Color(0xFFFAFAFA), fontSize: 9.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(widget.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
              const Spacer(),
              Text(modeLabel, style: TextStyle(color: activeColor, fontSize: 9.5, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),

          // Interactive Mode Segmented Toggle Bar
          Row(
            children: <Widget>[
              _modeChip(0, 'Definition', LucideIcons.bookOpen, const Color(0xFF71717A)),
              const SizedBox(width: 4),
              _modeChip(1, 'Application', LucideIcons.zap, const Color(0xFF71717A)),
              const SizedBox(width: 4),
              _modeChip(2, 'Takeaway', LucideIcons.target, const Color(0xFF71717A)),
            ],
          ),
          const SizedBox(height: 8),

          // Dynamic Content Box
          InkWell(
            onTap: () => setState(() => _activeViewIndex = (_activeViewIndex + 1) % 3),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E22),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3F3F46)),
              ),
              child: Text(
                currentText,
                style: const TextStyle(color: Colors.white, fontSize: 11.5, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(int index, String label, IconData icon, Color color) {
    final active = _activeViewIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeViewIndex = index),
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.25) : const Color(0x11FFFFFF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? color : const Color(0x22FFFFFF), width: active ? 1.2 : 1.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 10, color: active ? color : Colors.white54),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(fontSize: 9.5, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? Colors.white : Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashCard3DWidget extends StatefulWidget {
  const _FlashCard3DWidget({
    required this.question,
    required this.answer,
    required this.category,
    required this.isFlipped,
    required this.onTap,
  });

  final String question;
  final String answer;
  final String category;
  final bool isFlipped;
  final VoidCallback onTap;

  @override
  State<_FlashCard3DWidget> createState() => _FlashCard3DWidgetState();
}

class _FlashCard3DWidgetState extends State<_FlashCard3DWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: math.pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    if (widget.isFlipped) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant _FlashCard3DWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFlipped != widget.isFlipped) {
      if (widget.isFlipped) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value;
          final isBack = angle >= math.pi / 2;
          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            alignment: Alignment.center,
            child: isBack
                ? Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _buildCardContent(
                      isBack: true,
                      category: widget.category,
                      text: widget.answer,
                    ),
                  )
                : _buildCardContent(
                    isBack: false,
                    category: widget.category,
                    text: widget.question,
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCardContent({
    required bool isBack,
    required String category,
    required String text,
  }) {
    final themeColor = isBack ? const Color(0xFFFAFAFA) : const Color(0xFFE4E4E7);
    final bgColor = isBack ? const Color(0xFF27272A) : const Color(0xFF1F1F22);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3F3F46), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: themeColor.withValues(alpha: 0.5)),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      category.toUpperCase(),
                      style: TextStyle(
                        color: themeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isBack ? 'ANSWER' : 'QUESTION',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          SingleChildScrollView(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isBack ? 13 : 14.5,
                fontWeight: isBack ? FontWeight.w500 : FontWeight.bold,
                height: 1.45,
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(LucideIcons.rotateCw, size: 12, color: Colors.white54),
              SizedBox(width: 4),
              Text(
                'Click card to flip',
                style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
