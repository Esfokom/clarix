import 'package:flutter/material.dart';

import '../application/brain_trust_debater_service.dart';

class BrainTrustPanelWidget extends StatefulWidget {
  const BrainTrustPanelWidget({
    super.key,
    required this.service,
    required this.topic,
    required this.documentTexts,
  });

  final BrainTrustDebaterService service;
  final String topic;
  final Map<String, String> documentTexts;

  @override
  State<BrainTrustPanelWidget> createState() => _BrainTrustPanelWidgetState();
}

class _BrainTrustPanelWidgetState extends State<BrainTrustPanelWidget> {
  final TextEditingController _questionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.service.currentSession == null) {
      _startDebate();
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _startDebate() async {
    await widget.service.runPanelDebate(
      topic: widget.topic,
      documentTexts: widget.documentTexts,
    );
  }

  Color _getPersonaColor(PanelPersonaRole role) {
    switch (role) {
      case PanelPersonaRole.optimist:
        return Colors.tealAccent;
      case PanelPersonaRole.skeptic:
        return Colors.orangeAccent;
      case PanelPersonaRole.methodologist:
        return Colors.cyanAccent;
      case PanelPersonaRole.moderator:
        return Colors.amberAccent;
    }
  }

  IconData _getPersonaIcon(PanelPersonaRole role) {
    switch (role) {
      case PanelPersonaRole.optimist:
        return Icons.trending_up;
      case PanelPersonaRole.skeptic:
        return Icons.shield;
      case PanelPersonaRole.methodologist:
        return Icons.science;
      case PanelPersonaRole.moderator:
        return Icons.record_voice_over;
    }
  }

  Future<void> _handleAskQuestion() async {
    final q = _questionController.text.trim();
    if (q.isEmpty) return;

    _questionController.clear();
    await widget.service.askPanelQuestion(q);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.service.currentSession;

    return Dialog(
      backgroundColor: const Color(0xFF191924),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 860,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              children: [
                const Icon(Icons.groups, color: Colors.amberAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multi-Document "Brain-Trust" Virtual Panel',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Topic: ${widget.topic}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    'Gemma 4 Co-T Panel',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Loaded Documents Chips
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.documentTexts.keys.map((title) {
                return Chip(
                  avatar: const Icon(Icons.description, size: 14, color: Colors.white70),
                  label: Text(title, style: const TextStyle(fontSize: 11, color: Colors.white)),
                  backgroundColor: const Color(0xFF28283D),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            if (widget.service.isDebating && session == null)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.amberAccent),
                      SizedBox(height: 16),
                      Text(
                        'Synthesizing multi-document panel debate with Gemma 4 Co-T reasoning...',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            else if (session != null) ...[
              // Consensus Summary Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        session.consensusSummary,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Debate Feed
              Expanded(
                child: ListView.separated(
                  itemCount: session.turns.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final turn = session.turns[index];
                    final color = _getPersonaColor(turn.role);
                    final icon = _getPersonaIcon(turn.role);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF232336),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: color.withValues(alpha: 0.2),
                                child: Icon(icon, color: color, size: 16),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                turn.personaName,
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Cited: ${turn.citedDocTitle}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            turn.statement,
                            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                          ),
                          if (turn.keyPoints.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: turn.keyPoints.map((point) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '• $point',
                                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Ask Panel Prompt Input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ask the Brain-Trust Panel a follow-up question...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF28283D),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _handleAskQuestion(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: widget.service.isDebating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.send, size: 16),
                    label: const Text('Ask Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: widget.service.isDebating ? null : _handleAskQuestion,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
