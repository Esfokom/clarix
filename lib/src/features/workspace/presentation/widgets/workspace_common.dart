import 'package:flutter/material.dart';
import 'package:smooth_corner/smooth_corner.dart';

class WorkspaceColors {
  static const Color canvas = Color(0xFF09090B);
  static const Color canvasRaised = Color(0xFF0F1013);
  static const Color panel = Color(0xFF111216);
  static const Color panelRaised = Color(0xFF18191E);
  static const Color viewerBackground = Color(0xFF0B0C0F);
  static const Color border = Color(0xFF27272A);
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
        child: Padding(
          padding: padding,
          child: child,
        ),
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
