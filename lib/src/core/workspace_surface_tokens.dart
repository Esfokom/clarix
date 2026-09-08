import 'package:flutter/material.dart';

import 'theme_profile.dart';

class _Palette {
  const _Palette({
    required this.canvas,
    required this.canvasRaised,
    required this.panel,
    required this.panelRaised,
    required this.viewerBackground,
    required this.border,
    required this.textStrong,
    required this.textMuted,
    required this.textFaint,
  });

  final Color canvas;
  final Color canvasRaised;
  final Color panel;
  final Color panelRaised;
  final Color viewerBackground;
  final Color border;
  final Color textStrong;
  final Color textMuted;
  final Color textFaint;
}

const _Palette _darkPalette = _Palette(
  canvas: Color(0xFF2F2F2F),
  canvasRaised: Color(0xFF343434),
  panel: Color(0xFF343434),
  panelRaised: Color(0xFF3A3A3A),
  viewerBackground: Color(0xFF292929),
  border: Color(0xFF484848),
  textStrong: Color(0xFFFAFAFA),
  textMuted: Color(0xFFA1A1AA),
  textFaint: Color(0xFF71717A),
);

const _Palette _lightPalette = _Palette(
  canvas: Color(0xFFF4F4F5),
  canvasRaised: Color(0xFFFAFAFA),
  panel: Color(0xFFFFFFFF),
  panelRaised: Color(0xFFF4F4F5),
  viewerBackground: Color(0xFFD4D4D8),
  border: Color(0xFFE4E4E7),
  textStrong: Color(0xFF18181B),
  textMuted: Color(0xFF52525B),
  textFaint: Color(0xFFA1A1AA),
);

const Color _backdrop = Color(0xAA020203);
const Color _warning = Color(0xFFF59E0B);

/// Brightness- and accent-resolved surface colors for the custom-painted
/// workspace chrome. Replaces the app's static color constants so every
/// panel actually responds to the user's theme mode and accent choice.
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
    required this.backdrop,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.selection,
  });

  factory WorkspaceSurfaceTokens.fromProfile(
    ClarixThemeProfile profile,
    BuildContext context,
  ) {
    final Brightness brightness = Theme.of(context).brightness;
    final _Palette base = brightness == Brightness.dark
        ? _darkPalette
        : _lightPalette;
    final ClarixThemeTokens theme = resolveThemeTokens(profile);
    final Color tint = theme.accent.withValues(alpha: 0.035);
    return WorkspaceSurfaceTokens._(
      canvas: Color.alphaBlend(tint, base.canvas),
      canvasRaised: Color.alphaBlend(tint, base.canvasRaised),
      panel: Color.alphaBlend(tint, base.panel),
      panelRaised: Color.alphaBlend(tint, base.panelRaised),
      viewerBackground: base.viewerBackground,
      border: Color.alphaBlend(
        theme.accent.withValues(alpha: 0.09),
        base.border,
      ),
      textStrong: base.textStrong,
      textMuted: base.textMuted,
      textFaint: base.textFaint,
      warning: _warning,
      backdrop: _backdrop,
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
  final Color backdrop;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final Color selection;
}
