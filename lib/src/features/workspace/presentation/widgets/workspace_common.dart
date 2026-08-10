import 'package:flutter/material.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../../core/theme_profile.dart';

class WorkspaceColors {
  static const Color canvas = Color(0xFF2F2F2F);
  static const Color canvasRaised = Color(0xFF343434);
  static const Color panel = Color(0xFF343434);
  static const Color panelRaised = Color(0xFF3A3A3A);
  static const Color viewerBackground = Color(0xFF292929);
  static const Color border = Color(0xFF484848);
  static const Color backdrop = Color(0xAA020203);
  static const Color textStrong = Color(0xFFFAFAFA);
  static const Color textMuted = Color(0xFFA1A1AA);
  static const Color textFaint = Color(0xFF71717A);
  static const Color accent = Color(0xFFE4E4E7);
  static const Color accentSoft = Color(0xFF202229);
  static const Color accentBorder = Color(0xFF3F3F46);
  static const Color warning = Color(0xFFF59E0B);
  static const Color selection = Color(0x3038BDF8);
}

/// Semantic workspace colors derived from the active Clarix theme profile.
///
/// The neutral surfaces remain deliberately calm while selection, focus, and
/// interactive controls inherit the user's chosen accent.
class WorkspaceSurfaceTokens {
  const WorkspaceSurfaceTokens._({
    required this.canvas,
    required this.canvasRaised,
    required this.panel,
    required this.panelRaised,
    required this.viewerBackground,
    required this.border,
    required this.textStrong,
    required this.textMuted,
    required this.textFaint,
    required this.warning,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.selection,
  });

  factory WorkspaceSurfaceTokens.fromProfile(ClarixThemeProfile profile) {
    final ClarixThemeTokens theme = resolveThemeTokens(profile);
    final Color tint = theme.accent.withValues(alpha: 0.035);
    return WorkspaceSurfaceTokens._(
      canvas: Color.alphaBlend(tint, WorkspaceColors.canvas),
      canvasRaised: Color.alphaBlend(tint, WorkspaceColors.canvasRaised),
      panel: Color.alphaBlend(tint, WorkspaceColors.panel),
      panelRaised: Color.alphaBlend(tint, WorkspaceColors.panelRaised),
      viewerBackground: WorkspaceColors.viewerBackground,
      border: Color.alphaBlend(
        theme.accent.withValues(alpha: 0.09),
        WorkspaceColors.border,
      ),
      textStrong: WorkspaceColors.textStrong,
      textMuted: WorkspaceColors.textMuted,
      textFaint: WorkspaceColors.textFaint,
      warning: WorkspaceColors.warning,
      accent: theme.accent,
      accentSoft: theme.accentSoft,
      accentBorder: theme.accentBorder,
      selection: theme.accent.withValues(alpha: 0.26),
    );
  }

  final Color canvas;
  final Color canvasRaised;
  final Color panel;
  final Color panelRaised;
  final Color viewerBackground;
  final Color border;
  final Color textStrong;
  final Color textMuted;
  final Color textFaint;
  final Color warning;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final Color selection;
}

class SurfaceBlock extends StatelessWidget {
  const SurfaceBlock({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SmoothClipRRect(
      smoothness: 0.82,
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: WorkspaceColors.border),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: WorkspaceColors.panel),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: WorkspaceColors.textFaint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class SidebarEmpty extends StatelessWidget {
  const SidebarEmpty({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: WorkspaceColors.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WorkspaceColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: WorkspaceColors.textFaint,
          fontSize: 10.5,
        ),
      ),
    );
  }
}
