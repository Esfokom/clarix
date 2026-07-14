import 'package:clarix/src/features/reader_diagnostics/application/diagnostic_pdf_picker.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/diagnostic_viewer_chrome.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class StockPdfrxScreen extends StatefulWidget {
  const StockPdfrxScreen({
    this.pickPdf = pickDiagnosticPdf,
    this.onBack,
    super.key,
  });

  final DiagnosticPdfPicker pickPdf;
  final VoidCallback? onBack;

  @override
  State<StockPdfrxScreen> createState() => _StockPdfrxScreenState();
}

class _StockPdfrxScreenState extends State<StockPdfrxScreen> {
  late final PdfViewerController _controller;
  late final ValueNotifier<DiagnosticViewerStatus> _status;
  late final VoidCallback _controllerListener;
  String? _path;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _status = ValueNotifier<DiagnosticViewerStatus>(
      const DiagnosticViewerStatus(),
    );
    _controllerListener = _syncStatus;
    _controller.addListener(_controllerListener);
  }

  @override
  void dispose() {
    _controller.removeListener(_controllerListener);
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? path = _path;
    final Widget viewer = path == null
        ? const SizedBox.expand()
        : PdfViewer.file(
            path,
            key: ValueKey<String>(path),
            controller: _controller,
            params: const PdfViewerParams(),
          );

    return ValueListenableBuilder<DiagnosticViewerStatus>(
      valueListenable: _status,
      builder: (
        BuildContext context,
        DiagnosticViewerStatus status,
        Widget? child,
      ) {
        return DiagnosticViewerChrome(
          viewer: viewer,
          status: status.label,
          onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
          onOpenPdf: _openPdf,
        );
      },
    );
  }

  Future<void> _openPdf() async {
    final String? path = await widget.pickPdf();
    if (!mounted || path == null) {
      return;
    }
    setState(() => _path = path);
  }

  void _syncStatus() {
    if (!_controller.isReady) {
      return;
    }
    _status.value = DiagnosticViewerStatus(
      pageNumber: _controller.pageNumber,
      zoom: _controller.currentZoom,
    );
  }
}

class DiagnosticViewerStatus {
  const DiagnosticViewerStatus({this.pageNumber, this.zoom = 1});

  final int? pageNumber;
  final double zoom;

  String get label {
    final int? page = pageNumber;
    if (page == null) {
      return 'Open a PDF to test stock pdfrx input behavior.';
    }
    return 'Page $page at ${(zoom * 100).round()}%';
  }
}
