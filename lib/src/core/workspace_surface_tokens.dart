import 'package:flutter/material.dart';

import 'theme_profile.dart';

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
