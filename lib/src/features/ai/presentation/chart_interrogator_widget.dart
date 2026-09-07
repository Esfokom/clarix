import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../application/living_document_service.dart';

class ChartInterrogatorWidget extends StatefulWidget {
  const ChartInterrogatorWidget({
    super.key,
    required this.livingDocumentService,
    this.chartImageBytes,
  });

  final LivingDocumentService livingDocumentService;
  final Uint8List? chartImageBytes;

  @override
  State<ChartInterrogatorWidget> createState() => _ChartInterrogatorWidgetState();
}

class _ChartInterrogatorWidgetState extends State<ChartInterrogatorWidget> {
  final TextEditingController _questionController = TextEditingController(
    text: 'Analyze this trend line. What is the percentage drop between Q2 and Q3?',
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.livingDocumentService,
      builder: (context, _) {
        final result = widget.livingDocumentService.lastChartResult;
        final isProcessing = widget.livingDocumentService.isProcessing;
        final scenery = widget.livingDocumentService.currentScenery;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x331E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x3338BDF8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.barChart2, size: 16, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 6),
                  const Text('Spatial Chart Interrogator', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x3310B981),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.volume2, size: 10, color: Color(0xFF34D399)),
                        const SizedBox(width: 4),
                        Text('Scenery: ${scenery.name.toUpperCase()}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 9, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      style: const TextStyle(color: Colors.white, fontSize: 11.5),
                      decoration: InputDecoration(
                        hintText: 'Ask a visual chart question...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0x440F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0x3364748B))),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () async {
                            final bytes = widget.chartImageBytes ?? Uint8List.fromList([1, 2, 3, 4]);
                            await widget.livingDocumentService.interrogateChartRegion(
                              bytes,
                              _questionController.text.trim(),
                            );
                          },
                    icon: Icon(isProcessing ? LucideIcons.loader2 : LucideIcons.scan, size: 14),
                    label: Text(isProcessing ? 'Analyzing...' : 'Analyze Crop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
              if (result != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x66020617),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x2238BDF8)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Q: ${result.question}', style: const TextStyle(color: Color(0xFF7DD3FC), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(result.analysisText, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
