import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../application/gemma_timeline_service.dart';

class TimelineSeekbarWidget extends StatelessWidget {
  const TimelineSeekbarWidget({
    super.key,
    required this.timelineService,
  });

  final GemmaTimelineService timelineService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: timelineService,
      builder: (context, _) {
        final events = timelineService.timelineEvents;
        if (events.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            child: const Text('No timeline events extracted yet. Click extract timeline to analyze document chronology.', style: TextStyle(color: Colors.white60, fontSize: 11)),
          );
        }

        final activeIndex = timelineService.activeEventIndex;
        final activeEvent = timelineService.activeEvent ?? events.first;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x331E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x336366F1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.history, size: 15, color: Color(0xFF818CF8)),
                  const SizedBox(width: 6),
                  Text(
                    'Dynamic Time-Travel Chronology (${events.length} Events)',
                    style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x336366F1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Page ${activeEvent.pageNumber}',
                      style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Timeline Event Scrubber Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  activeTrackColor: const Color(0xFF818CF8),
                  inactiveTrackColor: const Color(0x3364748B),
                  thumbColor: const Color(0xFFC084FC),
                ),
                child: Slider(
                  value: activeIndex.toDouble(),
                  min: 0,
                  max: (events.length - 1).toDouble(),
                  divisions: events.length > 1 ? events.length - 1 : 1,
                  onChanged: (val) {
                    timelineService.setActiveEventIndex(val.round());
                  },
                ),
              ),
              const SizedBox(height: 6),
              // Active Event Details Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x66020617),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x22818CF8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(activeEvent.timestamp, style: const TextStyle(color: Color(0xFFC084FC), fontSize: 10.5, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text('• ${activeEvent.category}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(activeEvent.title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(activeEvent.description, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
