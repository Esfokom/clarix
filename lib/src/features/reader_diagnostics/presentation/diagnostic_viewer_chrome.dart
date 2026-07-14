import 'package:flutter/material.dart';

class DiagnosticViewerChrome extends StatefulWidget {
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
  State<DiagnosticViewerChrome> createState() =>
      _DiagnosticViewerChromeState();
}

class _DiagnosticViewerChromeState extends State<DiagnosticViewerChrome> {
  bool _chromeHidden = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: KeyedSubtree(
            key: const Key('diagnostic-viewer-surface'),
            child: widget.viewer,
          ),
        ),
        if (!_chromeHidden)
          Positioned.fill(
            child: Stack(
              key: const Key('diagnostic-chrome-controls'),
              children: <Widget>[
                Positioned(
                  top: 12,
                  left: 12,
                  child: TextButton(
                    key: const Key('diagnostic-back'),
                    onPressed: widget.onBack,
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
                        onPressed: widget.onOpenPdf,
                        child: const Text('Open PDF'),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Text(widget.status),
                ),
              ],
            ),
          ),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: const Color(0xD91B1D22),
              shape: const CircleBorder(),
              child: IconButton(
                key: const Key('diagnostic-chrome-toggle'),
                tooltip: _chromeHidden
                    ? 'Show viewer controls'
                    : 'Hide viewer controls',
                onPressed: () => setState(
                  () => _chromeHidden = !_chromeHidden,
                ),
                icon: Icon(
                  _chromeHidden ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
