part of 'ai_side_pane.dart';

class _DocumentComposer extends StatelessWidget {
  const _DocumentComposer({
    required this.controller,
    required this.voiceInput,
    required this.enabled,
    required this.isBusy,
    required this.hintText,
    required this.onSend,
    required this.onStop,
    required this.colors,
    required this.runtimeLabel,
    required this.runtimeIconPath,
    required this.selectedRuntimeId,
    required this.localModels,
    required this.providerProfiles,
    required this.onSelectRuntime,
    required this.runtimePickerEnabled,
    required this.contextPercent,
    required this.estimatedTokens,
    required this.contextLimit,
  });

  final TextEditingController controller;
  final VoiceInputController voiceInput;
  final bool enabled;
  final bool isBusy;
  final String hintText;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final WorkspaceSurfaceTokens colors;
  final String runtimeLabel;
  final String runtimeIconPath;
  final String? selectedRuntimeId;
  final List<LocalModelProfile> localModels;
  final List<AiProviderProfile> providerProfiles;
  final ValueChanged<String> onSelectRuntime;
  final bool runtimePickerEnabled;
  final int contextPercent;
  final int estimatedTokens;
  final int contextLimit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Material(
        color: Colors.transparent,
        child: Container(
          key: const Key('document-composer'),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 9),
          decoration: BoxDecoration(
            color: colors.panelRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const Key('document-composer-input'),
                controller: controller,
                enabled: enabled,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                style: TextStyle(
                  color: colors.textStrong,
                  fontSize: 12.5,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: TextStyle(color: colors.textFaint, fontSize: 12.5),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: voiceInput,
                builder: (BuildContext context, Widget? child) {
                  final bool isRecording =
                      voiceInput.status == VoiceInputStatus.recording;
                  final bool isTranscribing =
                      voiceInput.status == VoiceInputStatus.transcribing;
                  final String? voiceStatus = isTranscribing
                      ? 'Transcribing voice…'
                      : voiceInput.errorMessage;
                  return Row(
                    children: <Widget>[
                      _ComposerRuntimePicker(
                        label: runtimeLabel,
                        iconPath: runtimeIconPath,
                        selectedRuntimeId: selectedRuntimeId,
                        localModels: localModels,
                        providerProfiles: providerProfiles,
                        onSelected: onSelectRuntime,
                        enabled: runtimePickerEnabled,
                        colors: colors,
                      ),
                      const SizedBox(width: 8),
                      _ContextUsageRing(
                        percent: contextPercent,
                        estimatedTokens: estimatedTokens,
                        contextLimit: contextLimit,
                        colors: colors,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          voiceStatus ?? '',
                          key: const Key('voice-input-status'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: voiceInput.errorMessage == null
                                ? colors.textFaint
                                : colors.warning,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: isRecording
                            ? 'Stop recording'
                            : isTranscribing
                            ? 'Transcribing voice input'
                            : 'Start voice input',
                        child: IconButton(
                          key: const Key('document-composer-voice'),
                          onPressed:
                              isTranscribing || (!enabled && !isRecording)
                              ? null
                              : voiceInput.toggle,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            maximumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            backgroundColor: isRecording
                                ? colors.warning
                                : colors.panelRaised,
                            disabledBackgroundColor: colors.border,
                            foregroundColor: isRecording
                                ? colors.canvas
                                : colors.textMuted,
                            disabledForegroundColor: colors.textFaint,
                          ),
                          icon: isTranscribing
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: colors.textFaint,
                                  ),
                                )
                              : Icon(
                                  isRecording
                                      ? LucideIcons.square
                                      : LucideIcons.mic,
                                  size: isRecording ? 13 : 16,
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder:
                            (BuildContext context, TextEditingValue value, _) {
                              final bool canSend =
                                  enabled &&
                                  !isRecording &&
                                  !isTranscribing &&
                                  value.text.trim().isNotEmpty;
                              return Tooltip(
                                message: isBusy
                                    ? 'Stop generating'
                                    : 'Send question',
                                child: IconButton(
                                  key: const Key('document-composer-send'),
                                  onPressed: isBusy
                                      ? onStop
                                      : (canSend ? onSend : null),
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(32, 32),
                                    maximumSize: const Size(32, 32),
                                    padding: EdgeInsets.zero,
                                    backgroundColor: isBusy
                                        ? colors.textMuted
                                        : colors.accent,
                                    disabledBackgroundColor: colors.border,
                                    foregroundColor: colors.canvas,
                                    disabledForegroundColor: colors.textFaint,
                                  ),
                                  icon: Icon(
                                    isBusy
                                        ? LucideIcons.square
                                        : LucideIcons.arrowUp,
                                    size: isBusy ? 13 : 16,
                                  ),
                                ),
                              );
                            },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _runtimeIconPath(String label) {
  final String normalized = label.toLowerCase();
  if (normalized.contains('gemma')) return 'assets/images/gemma-color.png';
  if (normalized.contains('deepseek')) return 'assets/images/deepseek.png';
  return 'assets/images/openai.png';
}

/// Model switcher living in the composer, where the question is written, with
/// a menu surfaced in the workspace palette instead of the Material default.
class _ComposerRuntimePicker extends StatelessWidget {
  const _ComposerRuntimePicker({
    required this.label,
    required this.iconPath,
    required this.selectedRuntimeId,
    required this.localModels,
    required this.providerProfiles,
    required this.onSelected,
    required this.enabled,
    required this.colors,
  });

  final String label;
  final String iconPath;
  final String? selectedRuntimeId;
  final List<LocalModelProfile> localModels;
  final List<AiProviderProfile> providerProfiles;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final bool hasOptions =
        localModels.isNotEmpty || providerProfiles.isNotEmpty;
    return PopupMenuButton<String>(
      key: const Key('ai-runtime-picker'),
      tooltip: 'Choose AI model',
      enabled: enabled && hasOptions,
      onSelected: onSelected,
      color: colors.panelRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 14,
      shadowColor: const Color(0x73000000),
      position: PopupMenuPosition.over,
      offset: const Offset(0, -10),
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
      shape: SmoothRectangleBorder(
        smoothness: 0.8,
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        ...localModels.map(
          (LocalModelProfile model) => _runtimeEntry(
            id: model.id,
            label: model.label,
            iconPath: 'assets/images/gemma-color.png',
            trailingLabel: 'On device',
          ),
        ),
        ...providerProfiles.map(
          (AiProviderProfile profile) => _runtimeEntry(
            id: profile.id,
            label: profile.label,
            iconPath: _runtimeIconPath(profile.label),
          ),
        ),
      ],
      child: SmoothContainer(
        smoothness: 0.8,
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: colors.border),
        color: colors.panel,
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(iconPath, width: 13, height: 13),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                label,
                key: const Key('ai-runtime-picker-label'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(LucideIcons.chevronDown, color: colors.textFaint, size: 12),
          ],
        ),
      ),
    );
  }

  PopupMenuEntry<String> _runtimeEntry({
    required String id,
    required String label,
    required String iconPath,
    String? trailingLabel,
  }) {
    return PopupMenuItem<String>(
      value: id,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: _RuntimeMenuItem(
        label: label,
        iconPath: iconPath,
        trailingLabel: trailingLabel,
        isSelected: id == selectedRuntimeId,
        colors: colors,
      ),
    );
  }
}

class _RuntimeMenuItem extends StatelessWidget {
  const _RuntimeMenuItem({
    required this.label,
    required this.iconPath,
    required this.isSelected,
    required this.colors,
    this.trailingLabel,
  });

  final String label;
  final String iconPath;
  final bool isSelected;
  final WorkspaceSurfaceTokens colors;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Image.asset(iconPath, width: 18, height: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? colors.textStrong : colors.textMuted,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      if (trailingLabel != null && !isSelected)
        Text(
          trailingLabel!,
          style: TextStyle(color: colors.textFaint, fontSize: 10),
        ),
      if (isSelected) ...<Widget>[
        const SizedBox(width: 8),
        Icon(LucideIcons.check, size: 14, color: colors.accent),
      ],
    ],
  );
}

/// Conversation context budget, drawn as a ring in the composer where the
/// question is being written rather than as a number in the header.
class _ContextUsageRing extends StatelessWidget {
  const _ContextUsageRing({
    required this.percent,
    required this.estimatedTokens,
    required this.contextLimit,
    required this.colors,
  });

  final int percent;
  final int estimatedTokens;
  final int contextLimit;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    final bool nearLimit = percent >= 85;
    return Tooltip(
      message:
          'Conversation context: $estimatedTokens of $contextLimit tokens '
          '($percent%)',
      child: SizedBox(
        key: const Key('ai-context-usage'),
        width: 14,
        height: 14,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: (percent / 100).clamp(0, 1)),
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double value, Widget? child) =>
              CircularProgressIndicator(
                value: value,
                strokeWidth: 2,
                strokeCap: StrokeCap.round,
                backgroundColor: colors.border,
                color: nearLimit ? colors.warning : colors.accent,
              ),
        ),
      ),
    );
  }
}

class _ComposerLoadingIndicator extends StatefulWidget {
  const _ComposerLoadingIndicator({
    required this.colors,
    required this.statusMessage,
  });

  final WorkspaceSurfaceTokens colors;
  final String statusMessage;

  @override
  State<_ComposerLoadingIndicator> createState() =>
      _ComposerLoadingIndicatorState();
}

class _ComposerLoadingIndicatorState extends State<_ComposerLoadingIndicator>
    with SingleTickerProviderStateMixin {
  static const List<String> _words = <String>[
    'Reading',
    'Tracing',
    'Grounding',
    'Pondering',
    'Synthesizing',
    'Citing',
  ];

  late final AnimationController _animationController;
  late final Timer _wordTimer;
  int _wordIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _wordTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(() => _wordIndex = (_wordIndex + 1) % _words.length);
      }
    });
  }

  @override
  void dispose() {
    _wordTimer.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('composer-loader'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.statusMessage,
            key: const Key('ai-runtime-status'),
            style: TextStyle(color: widget.colors.textFaint, fontSize: 10.5),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ScaleTransition(
                scale: Tween<double>(begin: 0.72, end: 1.1).animate(
                  CurvedAnimation(
                    parent: _animationController,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.colors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 7, height: 7),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: _animationController,
                builder: (BuildContext context, Widget? child) => ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (Rect bounds) => LinearGradient(
                    colors: const <Color>[
                      WorkspaceColors.textMuted,
                      WorkspaceColors.textStrong,
                      WorkspaceColors.textMuted,
                    ],
                    stops: <double>[0, _animationController.value, 1],
                  ).createShader(bounds),
                  child: child,
                ),
                child: Text(
                  _words[_wordIndex],
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
