import 'package:flutter/material.dart';
import '../../../core/workspace_surface_tokens.dart';
import '../application/live_conversation_controller.dart';
import '../domain/live_conversation.dart';

class LiveConversationSurface extends StatelessWidget {
  const LiveConversationSurface({
    required this.state,
    required this.controller,
    required this.colors,
    required this.onStart,
    super.key,
  });
  final LiveConversationState state;
  final LiveConversationController controller;
  final WorkspaceSurfaceTokens colors;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) {
    final active =
        state.phase != LiveConversationPhase.idle &&
        state.phase != LiveConversationPhase.ended;
    final disabled = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.status,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ),
              if (active)
                TextButton(
                  key: const Key('end-live-conversation'),
                  onPressed: controller.end,
                  child: const Text('End voice conversation'),
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceOrb(
                  key: const Key('live-conversation-orb'),
                  amplitude: state.inputAmplitude,
                  speaking: state.phase == LiveConversationPhase.speaking,
                  animate: !disabled,
                ),
                const SizedBox(height: 18),
                if (!active)
                  FilledButton(
                    key: const Key('start-live-conversation'),
                    onPressed: onStart,
                    child: const Text('Start voice conversation'),
                  ),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      state.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.warning),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (state.userTranscript.isNotEmpty ||
            state.assistantTranscript.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Text(
              '${state.userTranscript}\n${state.assistantTranscript}',
              style: TextStyle(color: colors.textStrong, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({
    super.key,
    required this.amplitude,
    required this.speaking,
    required this.animate,
  });
  final double amplitude;
  final bool speaking;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    final double normalizedAmplitude = amplitude.clamp(0.0, 1.0);
    final double size = 104 + normalizedAmplitude * 30;
    return AnimatedContainer(
      duration: animate ? const Duration(milliseconds: 80) : Duration.zero,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF6D5EF7), Color(0xFF252050)],
        ),
        boxShadow: [
          BoxShadow(
            color:
                (speaking ? const Color(0xFF7FE8FF) : const Color(0xFFAFA3FF))
                    .withValues(alpha: .55),
            blurRadius: 24 + normalizedAmplitude * 30,
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}
