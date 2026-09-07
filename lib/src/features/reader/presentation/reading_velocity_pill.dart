import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../application/reading_velocity_tracker.dart';

final readingVelocityTrackerProvider =
    Provider.family<ReadingVelocityTracker, String>((ref, documentId) {
  final tracker = ReadingVelocityTracker();
  ref.onDispose(() => tracker.dispose());
  return tracker;
});

class ReadingVelocityPill extends ConsumerWidget {
  const ReadingVelocityPill({
    super.key,
    required this.documentId,
    required this.currentPage,
    required this.totalPages,
    this.pageText,
  });

  final String documentId;
  final int currentPage;
  final int totalPages;
  final String? pageText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = ref.watch(readingVelocityTrackerProvider(documentId));

    // Notify tracker of page navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (tracker.currentPage != currentPage || tracker.totalPages != totalPages) {
        tracker.onPageVisited(
          page: currentPage,
          totalPages: totalPages,
          pageText: pageText,
        );
      }
    });

    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        return Tooltip(
          message: '${tracker.finishTimeFormatted} • Click for details',
          child: InkWell(
            onTap: () => _showVelocityStatsDialog(context, tracker),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF27272A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3F3F46)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.timer, size: 12, color: Color(0xFFA1A1AA)),
                  const SizedBox(width: 5),
                  Text(
                    '${tracker.timeRemainingFormatted} • ~${tracker.currentWpm} WPM',
                    style: const TextStyle(
                      color: Color(0xFFFAFAFA),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVelocityStatsDialog(BuildContext context, ReadingVelocityTracker tracker) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18181B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF3F3F46)),
        ),
        title: const Row(
          children: [
            Icon(LucideIcons.gauge, size: 18, color: Color(0xFFA1A1AA)),
            SizedBox(width: 8),
            Text(
              'Reading Velocity & Pace Stats',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow(
              label: 'Active Reading Speed',
              value: '${tracker.currentWpm} WPM (Words Per Minute)',
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: 'Estimated Completion',
              value: tracker.finishTimeFormatted,
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: 'Time Remaining',
              value: tracker.timeRemainingFormatted,
            ),
            const SizedBox(height: 8),
            _StatRow(
              label: 'Current Progress',
              value: 'Page ${tracker.currentPage} of ${tracker.totalPages}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              tracker.resetSession();
              Navigator.of(ctx).pop();
            },
            child: const Text('Reset Session', style: TextStyle(color: Color(0xFFA1A1AA))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F3F46),
              foregroundColor: Colors.white,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        Text(value, style: const TextStyle(color: Color(0xFFFAFAFA), fontSize: 11.5, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
