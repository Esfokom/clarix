import 'dart:async';
import 'package:flutter/foundation.dart';

import 'kitten_tts_service.dart';

enum AudioBookState {
  idle,
  playing,
  paused,
  completed,
  error,
}

class OfflineAudioBookService extends ChangeNotifier {
  OfflineAudioBookService({
    required this.ttsService,
  });

  final KittenTtsService ttsService;
  List<String> _pageTexts = [];
  int _currentPageIndex = 0;
  int _currentParagraphIndex = 0;
  double _playbackSpeed = 1.0;
  String _selectedVoice = 'KittenTTS (Offline)';
  AudioBookState _state = AudioBookState.idle;
  String? _lastError;

  AudioBookState get state => _state;
  int get currentPageIndex => _currentPageIndex;
  int get totalPages => _pageTexts.isEmpty ? 1 : _pageTexts.length;
  double get playbackSpeed => _playbackSpeed;
  String get selectedVoice => _selectedVoice;
  bool get isPlaying => _state == AudioBookState.playing;
  bool get isPaused => _state == AudioBookState.paused;
  String? get lastError => _lastError;

  double get progressPercentage {
    if (_pageTexts.isEmpty) return 0.0;
    return ((_currentPageIndex + 1) / _pageTexts.length).clamp(0.0, 1.0);
  }

  String get currentParagraph {
    if (_pageTexts.isEmpty || _currentPageIndex >= _pageTexts.length) return '';
    final paragraphs = _pageTexts[_currentPageIndex].split('\n').where((p) => p.trim().isNotEmpty).toList();
    if (paragraphs.isEmpty) return _pageTexts[_currentPageIndex];
    return _currentParagraphIndex < paragraphs.length ? paragraphs[_currentParagraphIndex] : paragraphs.first;
  }

  void loadBook(List<String> pages) {
    _pageTexts = pages.isEmpty ? ['No document text available.'] : pages;
    _currentPageIndex = 0;
    _currentParagraphIndex = 0;
    _state = AudioBookState.idle;
    _lastError = null;
    notifyListeners();
  }

  Future<void> play() async {
    if (_pageTexts.isEmpty) return;

    _state = AudioBookState.playing;
    _lastError = null;
    notifyListeners();

    try {
      final textToSpeak = currentParagraph;
      ttsService.setSpeed(_playbackSpeed);
      await ttsService.speak(textToSpeak);

      if (_state == AudioBookState.playing) {
        _advanceToNextParagraph();
      }
    } catch (e) {
      _state = AudioBookState.error;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  void pause() {
    if (_state == AudioBookState.playing) {
      _state = AudioBookState.paused;
      ttsService.stop();
      notifyListeners();
    }
  }

  void resume() {
    if (_state == AudioBookState.paused) {
      play();
    }
  }

  void stop() {
    _state = AudioBookState.idle;
    _currentPageIndex = 0;
    _currentParagraphIndex = 0;
    ttsService.stop();
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.5, 2.5);
    ttsService.setSpeed(_playbackSpeed);
    notifyListeners();
  }

  void setSelectedVoice(String voice) {
    _selectedVoice = voice;
    ttsService.setVoice(voice);
    notifyListeners();
  }

  void skipToPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= totalPages) return;
    _currentPageIndex = pageIndex;
    _currentParagraphIndex = 0;
    notifyListeners();
    if (_state == AudioBookState.playing) {
      play();
    }
  }

  void nextPage() => skipToPage(_currentPageIndex + 1);
  void previousPage() => skipToPage(_currentPageIndex - 1);

  void _advanceToNextParagraph() {
    if (_pageTexts.isEmpty) return;
    final paragraphs = _pageTexts[_currentPageIndex].split('\n').where((p) => p.trim().isNotEmpty).toList();

    if (_currentParagraphIndex < paragraphs.length - 1) {
      _currentParagraphIndex++;
    } else if (_currentPageIndex < _pageTexts.length - 1) {
      _currentPageIndex++;
      _currentParagraphIndex = 0;
    } else {
      _state = AudioBookState.completed;
      notifyListeners();
      return;
    }

    if (_state == AudioBookState.playing) {
      play();
    }
  }
}
