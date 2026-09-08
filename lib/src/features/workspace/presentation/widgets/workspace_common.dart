import 'package:flutter/material.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../../core/workspace_surface_tokens.dart';
export '../../../../core/workspace_surface_tokens.dart';

class SurfaceBlock extends StatelessWidget {
  const SurfaceBlock({
    required this.child,
    required this.colors,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final WorkspaceSurfaceTokens colors;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SmoothClipRRect(
      smoothness: 0.82,
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: colors.border),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.panel),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({required this.label, required this.colors, super.key});

  final String label;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: colors.textFaint,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class SidebarEmpty extends StatelessWidget {
  const SidebarEmpty({
    required this.message,
    required this.colors,
    super.key,
  });

  final String message;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.textFaint, fontSize: 10.5),
      ),
    );
  }
}
