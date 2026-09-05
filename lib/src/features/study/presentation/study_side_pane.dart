import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme_controller.dart';
import '../../../core/theme_profile.dart';
import '../../../core/workspace_surface_tokens.dart';
import '../application/study_notifier.dart';
import '../application/study_providers.dart';
import '../application/study_service.dart';
import '../domain/study_models.dart';
import 'quiz_player_screen.dart';
import 'study_flashcard_view.dart';

class StudySidePane extends ConsumerStatefulWidget {
  const StudySidePane({
    required this.documentId,
    required this.onCollapse,
    this.onNavigateToPage,
    super.key,
  });

  final String documentId;
  final VoidCallback onCollapse;
  final ValueChanged<int>? onNavigateToPage;

  @override
  ConsumerState<StudySidePane> createState() => _StudySidePaneState();
}

class _StudySidePaneState extends ConsumerState<StudySidePane> {
  StudySetKind _kind = StudySetKind.flashcards;
  StudyDifficulty _difficulty = StudyDifficulty.medium;
  double _itemCount = 15;
  final TextEditingController _focusController = TextEditingController();
  bool _optionsExpanded = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(studyNotifierProvider.notifier).loadSets(widget.documentId),
    );
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    final StudyFeatureState state =
        ref.watch(studyNotifierProvider).value ?? StudyFeatureState.initial();
    final List<StudySet> sets =
        state.setsByDocument[widget.documentId] ?? const <StudySet>[];

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.panel),
      child: Column(
        children: <Widget>[
          _buildHeader(colors),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildOptions(colors, state),
                  const SizedBox(height: 12),
                  if (state.pendingOffer != null)
                    _buildFallbackOffer(colors, state.pendingOffer!),
                  if (state.errorMessage != null) ...<Widget>[
                    _buildErrorBanner(colors, state.errorMessage!),
                    const SizedBox(height: 12),
                  ],
                  if (state.activeRun != null) ...<Widget>[
                    _buildRunProgress(colors, state.activeRun!),
                    const SizedBox(height: 12),
                  ],
                  _buildResults(colors, sets),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(WorkspaceSurfaceTokens colors) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: <Widget>[
        Icon(LucideIcons.graduationCap, size: 16, color: colors.textStrong),
        const SizedBox(width: 8),
        Text(
          'Study',
          style: TextStyle(
            color: colors.textStrong,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        ShadIconButton.ghost(
          icon: const Icon(LucideIcons.panelRightClose, size: 16),
          onPressed: widget.onCollapse,
        ),
      ],
    ),
  );

  Widget _buildOptions(WorkspaceSurfaceTokens colors, StudyFeatureState state) {
    final bool busy = state.activeRun != null;
    return _StudyCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _segmentButton(
                  colors,
                  label: 'Flashcards',
                  selected: _kind == StudySetKind.flashcards,
                  onTap: () => setState(() => _kind = StudySetKind.flashcards),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _segmentButton(
                  colors,
                  label: 'Quiz',
                  selected: _kind == StudySetKind.quiz,
                  onTap: () => setState(() => _kind = StudySetKind.quiz),
                ),
              ),
              const SizedBox(width: 8),
              ShadIconButton.ghost(
                icon: Icon(
                  _optionsExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                ),
                onPressed: () =>
                    setState(() => _optionsExpanded = !_optionsExpanded),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            child: _optionsExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Items: ${_itemCount.round()}',
                          style: TextStyle(color: colors.textMuted, fontSize: 12),
                        ),
                        Slider(
                          value: _itemCount,
                          min: 5,
                          max: 40,
                          divisions: 35,
                          onChanged: busy
                              ? null
                              : (double value) =>
                                    setState(() => _itemCount = value),
                        ),
                        const SizedBox(height: 8),
                        ShadSelect<StudyDifficulty>(
                          enabled: !busy,
                          placeholder: const Text('Difficulty'),
                          initialValue: _difficulty,
                          options: StudyDifficulty.values
                              .map(
                                (StudyDifficulty value) => ShadOption<StudyDifficulty>(
                                  value: value,
                                  child: Text(value.name),
                                ),
                              )
                              .toList(growable: false),
                          selectedOptionBuilder: (BuildContext context, StudyDifficulty value) =>
                              Text(value.name),
                          onChanged: (StudyDifficulty? value) {
                            if (value != null) setState(() => _difficulty = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        ShadInput(
                          controller: _focusController,
                          enabled: !busy,
                          placeholder: const Text(
                            'Optional: a topic to concentrate on',
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          ShadButton(
            enabled: !busy,
            onPressed: busy ? null : _generate,
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Widget _segmentButton(
    WorkspaceSurfaceTokens colors, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.panelRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? colors.accentBorder : colors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? colors.accent : colors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _buildRunProgress(WorkspaceSurfaceTokens colors, StudyRunState run) {
    final double progress = run.batchCount == 0
        ? 0
        : (run.batchIndex + 1) / run.batchCount;
    return _StudyCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            run.batchCount == 0
                ? 'Starting…'
                : 'Batch ${run.batchIndex + 1} of ${run.batchCount}',
            style: TextStyle(color: colors.textStrong, fontSize: 12),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: run.batchCount == 0 ? null : progress),
          const SizedBox(height: 6),
          Text(
            '${run.itemsAccepted} of ${run.itemsRequested} items',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ShadButton.outline(
              onPressed: () =>
                  ref.read(studyNotifierProvider.notifier).cancelRun(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackOffer(
    WorkspaceSurfaceTokens colors,
    StudyFallbackOffer offer,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _StudyCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'No connection — generate on-device with Gemma 4?',
            style: TextStyle(color: colors.textStrong, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Quality is lower and it may not finish.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: ShadButton.outline(
                  onPressed: () =>
                      ref.read(studyNotifierProvider.notifier).declineFallback(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ShadButton(
                  onPressed: () =>
                      ref.read(studyNotifierProvider.notifier).acceptFallback(),
                  child: const Text('Generate on-device'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildErrorBanner(WorkspaceSurfaceTokens colors, String message) =>
      _StudyCard(
        colors: colors,
        child: Text(
          message,
          style: TextStyle(color: colors.warning, fontSize: 12),
        ),
      );

  Widget _buildResults(WorkspaceSurfaceTokens colors, List<StudySet> sets) {
    if (sets.isEmpty) {
      return Text(
        'No study sets yet for this document.',
        style: TextStyle(color: colors.textFaint, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final StudySet set in sets) _buildResultTile(colors, set),
      ],
    );
  }

  Widget _buildResultTile(WorkspaceSurfaceTokens colors, StudySet set) {
    final int itemCount = set.kind == StudySetKind.flashcards
        ? set.cards.length
        : set.questions.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _StudyCard(
        colors: colors,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            Icon(
              set.kind == StudySetKind.flashcards
                  ? LucideIcons.layers
                  : LucideIcons.listChecks,
              size: 16,
              color: colors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    set.title,
                    style: TextStyle(color: colors.textStrong, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    children: <Widget>[
                      Text(
                        '$itemCount items',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      ),
                      if (set.generatedOnDevice)
                        _badge(colors, 'On-device'),
                      if (set.isPartial) _badge(colors, 'Partial'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.play, size: 16),
              onPressed: () => _open(set),
            ),
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 16),
              onPressed: () => ref
                  .read(studyNotifierProvider.notifier)
                  .deleteSet(widget.documentId, set.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(WorkspaceSurfaceTokens colors, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: colors.accentSoft,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(color: colors.accent, fontSize: 10),
    ),
  );

  void _generate() {
    final StudyGenerationConfig config = StudyGenerationConfig(
      kind: _kind,
      itemCount: _itemCount.round(),
      difficulty: _difficulty,
      focus: _focusController.text,
    );
    ref
        .read(studyNotifierProvider.notifier)
        .generate(documentId: widget.documentId, config: config);
  }

  void _open(StudySet set) {
    if (set.kind == StudySetKind.flashcards) {
      showDialog<void>(
        context: context,
        builder: (BuildContext context) => Dialog(
          child: SizedBox(
            width: 480,
            height: 560,
            child: StudyFlashcardView(
              studySet: set,
              onNavigateToPage: widget.onNavigateToPage,
            ),
          ),
        ),
      );
    } else {
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                  child: child,
                ),
              ),
          pageBuilder: (context, animation, secondaryAnimation) =>
              QuizPlayerScreen(studySet: set),
        ),
      );
    }
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final WorkspaceSurfaceTokens colors;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: colors.panelRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.border),
    ),
    child: child,
  );
}
