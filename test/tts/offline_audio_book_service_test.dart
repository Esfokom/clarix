import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/tts/tts.dart';

void main() {
  group('OfflineAudioBookService tests', () {
    test('initial state is idle with 1 page', () {
      final tts = KittenTtsService();
      final audioBook = OfflineAudioBookService(ttsService: tts);

      expect(audioBook.state, equals(AudioBookState.idle));
      expect(audioBook.currentPageIndex, equals(0));
      expect(audioBook.totalPages, equals(1));
      expect(audioBook.playbackSpeed, equals(1.0));
      expect(audioBook.isPlaying, isFalse);
    });

    test('loads book pages and updates progress percentage', () {
      final tts = KittenTtsService();
      final audioBook = OfflineAudioBookService(ttsService: tts);

      audioBook.loadBook(['Page 1 paragraph 1', 'Page 2 paragraph 1', 'Page 3 paragraph 1']);

      expect(audioBook.totalPages, equals(3));
      expect(audioBook.currentPageIndex, equals(0));
      expect(audioBook.progressPercentage, closeTo(0.333, 0.01));

      audioBook.skipToPage(1);
      expect(audioBook.currentPageIndex, equals(1));
      expect(audioBook.progressPercentage, closeTo(0.666, 0.01));
    });

    test('updates playback speed and selected voice', () {
      final tts = KittenTtsService();
      final audioBook = OfflineAudioBookService(ttsService: tts);

      audioBook.setPlaybackSpeed(1.5);
      expect(audioBook.playbackSpeed, equals(1.5));

      audioBook.setSelectedVoice('Piper-Offline');
      expect(audioBook.selectedVoice, equals('Piper-Offline'));
    });
  });
}
