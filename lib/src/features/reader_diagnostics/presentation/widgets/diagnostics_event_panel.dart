import 'dart:convert';
import 'dart:math';

import 'package:clarix/src/core/clarix_logger.dart';
import 'package:clarix/src/features/reader_diagnostics/application/reader_diagnostics_recorder.dart';
import 'package:clarix/src/features/reader_diagnostics/domain/reader_diagnostic_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef DiagnosticsCopyText = Future<void> Function(String value);

Future<void> _copyTextToClipboard(String value) async {
  await Clipboard.setData(ClipboardData(text: value));
}

class DiagnosticsEventPanel extends StatefulWidget {
  DiagnosticsEventPanel({
    required this.recorder,
    DiagnosticsCopyText? copyText,
    super.key,
  }) : copyText = copyText ?? _copyTextToClipboard;

  final ReaderDiagnosticsRecorder recorder;
  final DiagnosticsCopyText copyText;

  @override
  State<DiagnosticsEventPanel> createState() => _DiagnosticsEventPanelState();
}

class _DiagnosticsEventPanelState extends State<DiagnosticsEventPanel> {
  static const int _visibleEventLimit = 100;

  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('diagnostics-event-panel'),
      color: const Color(0xE61B1D22),
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildToolbar(),
            if (!_collapsed)
              SizedBox(
                key: const Key('diagnostics-event-list'),
                height: 280,
                child: ValueListenableBuilder<List<ReaderDiagnosticEvent>>(
                  valueListenable: widget.recorder.events,
                  builder: (
                    BuildContext context,
                    List<ReaderDiagnosticEvent> events,
                    Widget? child,
                  ) {
                    final int start = max(
                      0,
                      events.length - _visibleEventLimit,
                    );
                    final List<ReaderDiagnosticEvent> newest = events
                        .sublist(start)
                        .reversed
                        .toList(growable: false);
                    if (newest.isEmpty) {
                      return const Center(
                        child: Text(
                          'No diagnostic events.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: newest.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ReaderDiagnosticEvent event = newest[index];
                        return Padding(
                          key: Key(
                            'diagnostics-event-' + event.sequence.toString(),
                          ),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SelectableText(
                            jsonEncode(event.toJson()),
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'Events',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: widget.recorder.paused,
            builder: (BuildContext context, bool paused, Widget? child) {
              return IconButton(
                key: const Key('diagnostics-pause'),
                tooltip: paused ? 'Resume recording' : 'Pause recording',
                onPressed: () => widget.recorder.paused.value = !paused,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                color: Colors.white,
              );
            },
          ),
          IconButton(
            key: const Key('diagnostics-copy'),
            tooltip: 'Copy diagnostic JSON',
            onPressed: _copy,
            icon: const Icon(Icons.copy),
            color: Colors.white,
          ),
          IconButton(
            key: const Key('diagnostics-clear'),
            tooltip: 'Clear events',
            onPressed: widget.recorder.clear,
            icon: const Icon(Icons.delete_outline),
            color: Colors.white,
          ),
          IconButton(
            key: const Key('diagnostics-collapse'),
            tooltip: _collapsed ? 'Expand events' : 'Collapse events',
            onPressed: () => setState(() => _collapsed = !_collapsed),
            icon: Icon(
              _collapsed ? Icons.expand_more : Icons.expand_less,
            ),
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Future<void> _copy() async {
    try {
      await widget.copyText(widget.recorder.exportJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnostic JSON copied.')),
        );
      }
    } catch (error, stackTrace) {
      clarixLog.e(
        'Failed to copy diagnostic JSON',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not copy diagnostic JSON.')),
        );
      }
    }
  }
}
