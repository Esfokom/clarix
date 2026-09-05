import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/workspace_surface_tokens.dart';
import '../domain/study_models.dart';

class QuizResultsView extends StatelessWidget {
  const QuizResultsView({
    required this.studySet,
    required this.answers,
    required this.colors,
    required this.onRetake,
    required this.onBack,
    super.key,
  });

  final StudySet studySet;
  final Map<String, int> answers;
  final WorkspaceSurfaceTokens colors;
  final VoidCallback onRetake;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final List<QuizQuestion> questions = studySet.questions;
    final int correct = questions
        .where((QuizQuestion q) => answers[q.id] == q.correctIndex)
        .length;
    final double ratio = questions.isEmpty ? 0 : correct / questions.length;

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: ratio),
                    duration: const Duration(milliseconds: 600),
                    builder: (BuildContext context, double value, Widget? _) =>
                        CircularProgressIndicator(
                          value: value,
                          strokeWidth: 8,
                          backgroundColor: colors.panelRaised,
                          color: colors.accent,
                        ),
                  ),
                  Text(
                    '$correct/${questions.length}',
                    style: TextStyle(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: questions.length,
                itemBuilder: (BuildContext context, int index) {
                  final QuizQuestion question = questions[index];
                  final int? given = answers[question.id];
                  final bool wasCorrect = given == question.correctIndex;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.panelRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                wasCorrect ? Icons.check_circle : Icons.cancel,
                                color: wasCorrect ? Colors.green : colors.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  question.prompt,
                                  style: TextStyle(
                                    color: colors.textStrong,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your answer: ${given != null ? question.options[given] : "—"}',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                          if (!wasCorrect)
                            Text(
                              'Correct answer: ${question.options[question.correctIndex]}',
                              style: TextStyle(color: colors.textMuted, fontSize: 12),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            question.explanation,
                            style: TextStyle(color: colors.textFaint, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: onBack,
                      child: const Text('Back to pane'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShadButton(
                      onPressed: onRetake,
                      child: const Text('Retake'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
