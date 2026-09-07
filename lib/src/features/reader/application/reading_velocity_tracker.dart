import 'package:flutter/foundation.dart';

/// Real-time Reading Velocity Tracker
/// Measures user reading speed (words-per-minute / WPM) based on active page dwell time
/// and provides estimated time-to-read completion metrics.
class ReadingVelocityTracker extends ChangeNotifier {
  ReadingVelocityTracker({
    int defaultWpm = 250,
    this._averageWordsPerPage = 300,
  }) : _wpm = defaultWpm;

  final int _averageWordsPerPage;
  int _wpm;
  int _currentPage = 1;
  int _totalPages = 1;
  int _sessionWordsRead = 0;
  Duration _sessionReadingDuration = Duration.zero;
  DateTime? _pageStartTime;

  int get currentWpm => _wpm;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get sessionWordsRead => _sessionWordsRead;
  Duration get sessionReadingDuration => _sessionReadingDuration;

  /// Time remaining estimate based on current WPM and remaining pages
  Duration get estimatedTimeRemaining {
    final remainingPages = (_totalPages - _currentPage).clamp(0, 999999);
    if (remainingPages == 0) return Duration.zero;
    final remainingWords = remainingPages * _averageWordsPerPage;
    final minutes = remainingWords / (_wpm > 0 ? _wpm : 250);
    return Duration(seconds: (minutes * 60).round());
  }

  /// Estimated completion timestamp
  DateTime get estimatedFinishTime {
    return DateTime.now().add(estimatedTimeRemaining);
  }

  /// Formatted string like "3 mins left" or "Less than a min left"
  String get timeRemainingFormatted {
    final remaining = estimatedTimeRemaining;
    if (remaining.inSeconds == 0) return 'Complete';
    if (remaining.inMinutes < 1) return '< 1 min left';
    if (remaining.inHours < 1) return '${remaining.inMinutes} mins left';
    final hrs = remaining.inHours;
    final mins = remaining.inMinutes % 60;
    return '${hrs}h ${mins}m left';
  }

  /// Formatted completion time like "Finish at 4:15 PM"
  String get finishTimeFormatted {
    if (estimatedTimeRemaining.inSeconds == 0) return 'Done';
    final finish = estimatedFinishTime;
    final hour = finish.hour % 12 == 0 ? 12 : finish.hour % 12;
    final minute = finish.minute.toString().padLeft(2, '0');
    final period = finish.hour >= 12 ? 'PM' : 'AM';
    return 'Finish at $hour:$minute $period';
  }

  /// Call whenever active page changes or text content is updated
  void onPageVisited({
    required int page,
    required int totalPages,
    String? pageText,
  }) {
    final now = DateTime.now();

    if (_pageStartTime != null && _currentPage != page) {
      final dwellDuration = now.difference(_pageStartTime!);
      // Only count active dwell between 2s and 10 mins (ignore idle or fast skipping)
      if (dwellDuration.inSeconds >= 2 && dwellDuration.inMinutes <= 10) {
        _sessionReadingDuration += dwellDuration;
        final wordsOnPage = pageText != null && pageText.trim().isNotEmpty
            ? pageText.trim().split(RegExp(r'\s+')).length
            : _averageWordsPerPage;

        _sessionWordsRead += wordsOnPage;

        // Recalculate WPM if reading duration is at least 5 seconds
        if (_sessionReadingDuration.inSeconds >= 5 && _sessionWordsRead > 0) {
          final minutes = _sessionReadingDuration.inMilliseconds / (60 * 1000);
          final calculatedWpm = (_sessionWordsRead / minutes).round();
          // Clamp WPM between reasonable boundaries (60 to 1000 WPM)
          _wpm = calculatedWpm.clamp(60, 1000);
        }
      }
    }

    _currentPage = page;
    _totalPages = totalPages;
    _pageStartTime = now;
    notifyListeners();
  }

  /// Reset session stats
  void resetSession() {
    _sessionWordsRead = 0;
    _sessionReadingDuration = Duration.zero;
    _pageStartTime = DateTime.now();
    notifyListeners();
  }
}
