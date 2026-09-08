import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme_controller.dart';
import '../../../core/theme_profile.dart';
import '../../../core/workspace_surface_tokens.dart';
import '../domain/study_models.dart';

class StudyFlashcardView extends ConsumerStatefulWidget {
  const StudyFlashcardView({
    required this.studySet,
    this.onNavigateToPage,
    super.key,
  });

  final StudySet studySet;
  final ValueChanged<int>? onNavigateToPage;

  @override
  ConsumerState<StudyFlashcardView> createState() =>
      _StudyFlashcardViewState();
}

class _StudyFlashcardViewState extends ConsumerState<StudyFlashcardView> {
  int _index = 0;
  bool _flipped = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    final List<Flashcard> cards = widget.studySet.cards;
    if (cards.isEmpty) {
      return Center(
        child: Text(
          'This set has no flashcards.',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    final Flashcard card = cards[_index];

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is! KeyDownEvent) return;
        if (event.logicalKey == LogicalKeyboardKey.space) {
          setState(() => _flipped = !_flipped);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _next(cards.length);
        } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _previous();
        }
      },
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.canvas),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Text(
                '${_index + 1} / ${cards.length}',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _flipped = !_flipped),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      final bool showFront =
                          child.key == const ValueKey<String>('front');
                      final Animation<double> rotate = Tween<double>(
                        begin: showFront ? math.pi : 0,
                        end: showFront ? 0 : math.pi,
                      ).animate(animation);
                      return AnimatedBuilder(
                        animation: rotate,
                        child: child,
                        builder: (BuildContext context, Widget? child) {
                          final bool isUnder = rotate.value > math.pi / 2;
                          final double angle = isUnder
                              ? math.pi - rotate.value
                              : rotate.value;
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.001)
                              ..rotateY(angle * (isUnder ? -1 : 1)),
                            child: child,
                          );
                        },
                      );
                    },
                    child: _flipped
                        ? _face(colors, key: 'back', text: card.back)
                        : _face(colors, key: 'front', text: card.front),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (card.pageNumber != null)
                ShadButton.ghost(
                  onPressed: () =>
                      widget.onNavigateToPage?.call(card.pageNumber!),
                  child: Text('Page ${card.pageNumber}'),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  ShadButton.outline(
                    onPressed: _index == 0 ? null : _previous,
                    child: const Text('Previous'),
                  ),
                  ShadButton(
                    onPressed: () => _next(cards.length),
                    child: Text(_index == cards.length - 1 ? 'Restart' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _face(
    WorkspaceSurfaceTokens colors, {
    required String key,
    required String text,
  }) => Container(
    key: ValueKey<String>(key),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: colors.panelRaised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.border),
    ),
    child: SingleChildScrollView(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.textStrong, fontSize: 18),
      ),
    ),
  );

  void _next(int length) {
    setState(() {
      _flipped = false;
      _index = (_index + 1) % length;
    });
  }

  void _previous() {
    setState(() {
      _flipped = false;
      _index = math.max(0, _index - 1);
    });
  }
}
