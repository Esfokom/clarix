import 'package:flutter/material.dart';
import 'package:smooth_corner/smooth_corner.dart';

import '../../../../core/workspace_surface_tokens.dart';
export '../../../../core/workspace_surface_tokens.dart';

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
