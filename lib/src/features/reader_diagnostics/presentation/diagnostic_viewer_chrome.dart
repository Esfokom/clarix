import 'package:flutter/material.dart';

class DiagnosticViewerChrome extends StatelessWidget {
  const DiagnosticViewerChrome({
    required this.viewer,
    required this.status,
    required this.onBack,
    required this.onOpenPdf,
    this.trailing,
    super.key,
  });

  final Widget viewer;
  final String status;
  final VoidCallback onBack;
  final VoidCallback onOpenPdf;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: viewer),
        Positioned(
          top: 12,
          left: 12,
          child: TextButton(
            key: const Key('diagnostic-back'),
            onPressed: onBack,
            child: const Text('Back'),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextButton(
                key: const Key('stock-open-pdf'),
                onPressed: onOpenPdf,
                child: const Text('Open PDF'),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Text(status),
        ),
      ],
    );
  }
}
