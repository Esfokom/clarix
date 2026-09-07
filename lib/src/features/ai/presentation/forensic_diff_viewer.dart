import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../application/forensic_marginalia_service.dart';

class ForensicDiffViewer extends StatefulWidget {
  const ForensicDiffViewer({
    super.key,
    required this.service,
    required this.docATitle,
    required this.docAText,
    required this.docBTitle,
    required this.docBText,
  });

  final ForensicMarginaliaService service;
  final String docATitle;
  final String docAText;
  final String docBTitle;
  final String docBText;

  @override
  State<ForensicDiffViewer> createState() => _ForensicDiffViewerState();
}

class _ForensicDiffViewerState extends State<ForensicDiffViewer> {
  @override
  void initState() {
    super.initState();
    if (widget.service.lastReport == null) {
      _runComparison();
    }
  }

  Future<void> _runComparison() async {
    await widget.service.compareDocuments(
      docATitle: widget.docATitle,
      docAText: widget.docAText,
      docBTitle: widget.docBTitle,
      docBText: widget.docBText,
    );
  }

  Color _getCategoryColor(SemanticDiffCategory category) {
    switch (category) {
      case SemanticDiffCategory.legal:
        return Colors.redAccent;
      case SemanticDiffCategory.logical:
        return Colors.orangeAccent;
      case SemanticDiffCategory.structural:
        return Colors.blueAccent;
      case SemanticDiffCategory.editorial:
        return Colors.tealAccent;
    }
  }

  IconData _getIntentIcon(MarginaliaIntent intent) {
    switch (intent) {
      case MarginaliaIntent.highlight:
        return Icons.highlight;
      case MarginaliaIntent.redact:
        return Icons.search_off;
      case MarginaliaIntent.bookmark:
        return Icons.bookmark;
      case MarginaliaIntent.summarize:
        return Icons.summarize;
      case MarginaliaIntent.formula:
        return Icons.functions;
      case MarginaliaIntent.unknown:
        return Icons.draw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.service.lastReport;

    return Dialog(
      backgroundColor: const Color(0xFF1E1E2C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 840,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, color: Colors.purpleAccent, size: 28),
                const SizedBox(width: 12),
                Text(
                  '128K Forensic Semantic Diff & Marginalia',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    'Gemma 4 E4B 128K',
                    style: TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.service.isProcessing)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.purpleAccent),
                      SizedBox(height: 16),
                      Text(
                        'Analyzing semantic clauses & tone across 128K window...',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            else if (report != null) ...[
              // Summary Header Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D42),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Comparing: ${report.docATitle} ↔ ${report.docBTitle}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            report.executiveSummary,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          '${(report.overallSimilarity * 100).toInt()}%',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Text('Similarity', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          '${(report.riskLevel * 100).toInt()}%',
                          style: TextStyle(
                            color: report.riskLevel > 0.5 ? Colors.redAccent : Colors.orangeAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text('Risk Level', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Section tabs or split view
              Expanded(
                child: Row(
                  children: [
                    // Left Column: Semantic Diffs list
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Semantic Clause Variations (${report.items.length})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.separated(
                              itemCount: report.items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = report.items[index];
                                final catColor = _getCategoryColor(item.category);

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF27273A),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: catColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: catColor.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              item.category.name.toUpperCase(),
                                              style: TextStyle(color: catColor, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                          ),
                                          Text(
                                            'Risk: ${(item.riskScore * 100).toInt()}%',
                                            style: TextStyle(
                                              color: item.riskScore > 0.6 ? Colors.redAccent : Colors.amberAccent,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '- ${item.originalText}',
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '+ ${item.modifiedText}',
                                          style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Implication: ${item.implication}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right Column: Scribble-to-Action Log
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Marginalia Scribble Actions',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purpleAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.gesture, size: 16),
                                label: const Text('Simulate Scribble', style: TextStyle(fontSize: 11)),
                                onPressed: () async {
                                  final dummyBytes = Uint8List.fromList([1, 2, 3, 4]);
                                  await widget.service.parseMarginaliaScribble(
                                    scribbleImageBytes: dummyBytes,
                                    contextPageText: widget.docAText,
                                  );
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: widget.service.recentActions.isEmpty
                                ? Center(
                                    child: Text(
                                      'No handwritten scribble annotations parsed yet. Click "Simulate Scribble".',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: widget.service.recentActions.length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                                    itemBuilder: (context, idx) {
                                      final act = widget.service.recentActions[idx];
                                      return Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2A2A3E),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(_getIntentIcon(act.intent), color: Colors.purpleAccent, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    act.actionDescription,
                                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                                  ),
                                                  Text(
                                                    'Target: ${act.targetText}',
                                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
