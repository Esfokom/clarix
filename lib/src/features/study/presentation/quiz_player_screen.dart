import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme_controller.dart';
import '../../../core/theme_profile.dart';
import '../../../core/workspace_surface_tokens.dart';
import '../domain/study_models.dart';
import 'quiz_results_view.dart';

const Color _kSuccess = Color(0xFF34D399);
const Color _kDanger = Color(0xFFF87171);

class QuizPlayerScreen extends ConsumerStatefulWidget {
  const QuizPlayerScreen({required this.studySet, super.key});

  final StudySet studySet;

  @override
  ConsumerState<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends ConsumerState<QuizPlayerScreen> {
  int _index = 0;
  int? _selected;
  bool _locked = false;
  bool _finished = false;
  final Map<String, int> _answers = <String, int>{};

  bool get _canPopFreely => !_locked && _selected == null && _index == 0;

  @override
  Widget build(BuildContext context) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    final List<QuizQuestion> questions = widget.studySet.questions;

    Widget body;
    if (questions.isEmpty) {
      body = Center(
        child: Text(
          'This quiz has no questions.',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    } else if (_finished) {
      body = QuizResultsView(
        studySet: widget.studySet,
        answers: _answers,
        colors: colors,
        onRetake: () => setState(() {
          _index = 0;
          _selected = null;
          _locked = false;
          _finished = false;
          _answers.clear();
        }),
        onBack: () => Navigator.of(context).pop(),
      );
    } else {
      final QuizQuestion question = questions[_index];
      body = Column(
        children: <Widget>[
          _buildProgress(colors, questions.length),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildQuestionCard(colors, question),
                  const SizedBox(height: 16),
                  for (int i = 0; i < question.options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _optionTile(colors, question, i),
                    ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: _locked
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildExplanation(colors, question),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          _buildFooter(colors, questions.length),
        ],
      );
    }

    return PopScope(
      canPop: _canPopFreely,
      onPopInvokedWithResult: (bool didPop, void result) async {
        if (didPop) return;
        final bool confirmed = await _confirmExit(context) ?? false;
        if (confirmed && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _windowChrome(colors, title: widget.studySet.title, child: body),
    );
  }

  Widget _windowChrome(
    WorkspaceSurfaceTokens colors, {
    required String title,
    required Widget child,
  }) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6)),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          child: Material(
            color: colors.panel,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildTitleBar(colors, title),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildTitleBar(WorkspaceSurfaceTokens colors, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textStrong,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
        if (widget.studySet.generatedOnDevice) ...<Widget>[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'On-device',
              style: TextStyle(color: colors.accent, fontSize: 10),
            ),
          ),
        ],
        const SizedBox(width: 4),
        Tooltip(
          message: 'Exit quiz',
          child: Material(
            color: _kDanger.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final NavigatorState navigator = Navigator.of(context);
                if (!_canPopFreely) {
                  final bool confirmed = await _confirmExit(context) ?? false;
                  if (!confirmed) return;
                }
                navigator.pop();
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LucideIcons.x, size: 16, color: _kDanger),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildProgress(WorkspaceSurfaceTokens colors, int total) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (_index + 1) / total,
            minHeight: 4,
            backgroundColor: colors.panelRaised,
            color: colors.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Question ${_index + 1} of $total',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _buildQuestionCard(
    WorkspaceSurfaceTokens colors,
    QuizQuestion question,
  ) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: colors.panelRaised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(height: 4, color: colors.accent),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            question.prompt,
            style: TextStyle(
              color: colors.textStrong,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _optionTile(
    WorkspaceSurfaceTokens colors,
    QuizQuestion question,
    int optionIndex,
  ) {
    final bool isSelected = _selected == optionIndex;
    final bool isCorrect = optionIndex == question.correctIndex;
    Color background = colors.panel;
    Color border = colors.border;
    IconData? trailingIcon;
    Color? trailingColor;
    if (_locked) {
      if (isCorrect) {
        background = _kSuccess.withValues(alpha: 0.14);
        border = _kSuccess;
        trailingIcon = LucideIcons.checkCircle2;
        trailingColor = _kSuccess;
      } else if (isSelected && !isCorrect) {
        background = _kDanger.withValues(alpha: 0.14);
        border = _kDanger;
        trailingIcon = LucideIcons.xCircle;
        trailingColor = _kDanger;
      }
    } else if (isSelected) {
      border = colors.accent;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: border,
          width: isSelected || (_locked && isCorrect) ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _locked ? null : () => _select(question, optionIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    question.options[optionIndex],
                    style: TextStyle(color: colors.textStrong, fontSize: 15),
                  ),
                ),
                if (trailingIcon != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(trailingIcon, size: 18, color: trailingColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplanation(WorkspaceSurfaceTokens colors, QuizQuestion question) =>
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.accentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: 3, color: colors.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Why',
                      style: TextStyle(
                        color: colors.textStrong,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      question.explanation,
                      style: TextStyle(color: colors.textMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildFooter(WorkspaceSurfaceTokens colors, int total) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
    child: Row(
      children: <Widget>[
        if (_index > 0)
          ShadButton.ghost(
            onPressed: _previous,
            child: const Text('Back'),
          ),
        const Spacer(),
        ShadButton(
          onPressed: _locked ? () => _advance(total) : null,
          child: Text(_index == total - 1 ? 'Finish' : 'Next'),
        ),
      ],
    ),
  );

  void _select(QuizQuestion question, int optionIndex) {
    setState(() {
      _selected = optionIndex;
      _locked = true;
      _answers[question.id] = optionIndex;
    });
  }

  void _previous() {
    if (_index == 0) return;
    setState(() {
      _index--;
      final String previousQuestionId = widget.studySet.questions[_index].id;
      _selected = _answers[previousQuestionId];
      _locked = _selected != null;
    });
  }

  void _advance(int total) {
    if (_index == total - 1) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      final String nextQuestionId = widget.studySet.questions[_index].id;
      _selected = _answers[nextQuestionId];
      _locked = _selected != null;
    });
  }

  Future<bool?> _confirmExit(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Exit quiz?'),
      content: const Text('Your progress on this attempt will be lost.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Exit'),
        ),
      ],
    ),
  );
}
