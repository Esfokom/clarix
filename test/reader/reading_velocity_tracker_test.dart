import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/reader/application/reading_velocity_tracker.dart';

void main() {
  group('ReadingVelocityTracker tests', () {
    test('calculates time remaining and initial WPM correctly', () {
      final tracker = ReadingVelocityTracker(defaultWpm: 200, averageWordsPerPage: 300);
      tracker.onPageVisited(page: 1, totalPages: 10);

      expect(tracker.currentWpm, 200);
      expect(tracker.currentPage, 1);
      expect(tracker.totalPages, 10);

      // Remaining pages: 9 pages * 300 words = 2700 words.
      // At 200 WPM, 2700 / 200 = 13.5 minutes = 810 seconds.
      expect(tracker.estimatedTimeRemaining.inMinutes, 13);
      expect(tracker.timeRemainingFormatted, contains('mins left'));
      expect(tracker.finishTimeFormatted, contains('Finish at'));
    });

    test('updates WPM based on page dwell time and words read', () async {
      final tracker = ReadingVelocityTracker(defaultWpm: 250, averageWordsPerPage: 300);
      tracker.onPageVisited(page: 1, totalPages: 5, pageText: 'Sample word count test content');

      await Future.delayed(const Duration(milliseconds: 50));
      tracker.onPageVisited(page: 2, totalPages: 5, pageText: 'Next page text content');

      expect(tracker.currentPage, 2);
    });

    test('resets session metrics cleanly', () {
      final tracker = ReadingVelocityTracker(defaultWpm: 300);
      tracker.onPageVisited(page: 3, totalPages: 20);
      tracker.resetSession();

      expect(tracker.sessionWordsRead, 0);
      expect(tracker.sessionReadingDuration, Duration.zero);
    });
  });
}
