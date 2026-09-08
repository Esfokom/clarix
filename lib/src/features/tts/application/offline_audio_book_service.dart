import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/clarix_logger.dart';
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
  String _selectedVoice = 'Zira';
  AudioBookState _state = AudioBookState.idle;
  String _bookTitle = '';
  String? _loadedFilePath;
  String? _lastError;

  AudioBookState get state => _state;
  int get currentPageIndex => _currentPageIndex;
  int get totalPages => _pageTexts.isEmpty ? 1 : _pageTexts.length;
  double get playbackSpeed => _playbackSpeed;
  String get selectedVoice => _selectedVoice;
  String get bookTitle => _bookTitle;
  String? get loadedFilePath => _loadedFilePath;
  bool get isPlaying => _state == AudioBookState.playing;
  bool get isPaused => _state == AudioBookState.paused;
  String? get lastError => _lastError;

  int get currentParagraphIndex => _currentParagraphIndex;

  List<String> get currentParagraphs {
    if (_pageTexts.isEmpty || _currentPageIndex >= _pageTexts.length) return [];
    final raw = _pageTexts[_currentPageIndex];
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [raw];
    return lines;
  }

  double get progressPercentage {
    if (_pageTexts.isEmpty) return 0.0;
    return ((_currentPageIndex + 1) / _pageTexts.length).clamp(0.0, 1.0);
  }

  String get currentParagraph {
    final pars = currentParagraphs;
    if (pars.isEmpty) return '';
    return _currentParagraphIndex < pars.length ? pars[_currentParagraphIndex] : pars.first;
  }

  void loadBook(List<String> pages, {String? title, String? filePath}) {
    _pageTexts = pages.isEmpty ? ['No document text available.'] : pages;
    if (title != null && title.isNotEmpty) {
      _bookTitle = title;
    }
    if (filePath != null) {
      _loadedFilePath = filePath;
    }
    _currentPageIndex = 0;
    _currentParagraphIndex = 0;
    _state = AudioBookState.idle;
    _lastError = null;
    notifyListeners();
  }

  /// Extracts real page text directly from a PDF file using pdfrx.
  Future<void> loadPdfDocument(String filePath, String title) async {
    if (_loadedFilePath == filePath && _pageTexts.isNotEmpty) {
      return; // Already loaded this PDF
    }

    _loadedFilePath = filePath;
    _bookTitle = title;

    try {
      await pdfrxInitialize();
      final pdf = await PdfDocument.openFile(filePath);
      final List<String> pages = [];

      for (int i = 0; i < pdf.pages.length; i++) {
        final page = await pdf.pages[i].ensureLoaded();
        final textObj = await page.loadText();
        final rawText = textObj?.fullText.trim() ?? '';
        if (rawText.isNotEmpty) {
          pages.add(rawText);
        }
      }
      await pdf.dispose();

      if (pages.isNotEmpty) {
        _pageTexts = pages;
        _currentPageIndex = 0;
        _currentParagraphIndex = 0;
        _state = AudioBookState.idle;
        _lastError = null;
        notifyListeners();
        return;
      }
    } catch (e) {
      clarixLog.w('Failed to extract PDF text for audiobook: $e');
    }

    // Fallback if extraction returns empty or fails
    _pageTexts = ['Document contents for $title.'];
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
      await ttsService.speak(textToSpeak, voiceId: _selectedVoice);

      if (ttsService.state == KittenTtsState.error) {
        _state = AudioBookState.error;
        _lastError = ttsService.lastError ?? 'Audiobook playback error';
        notifyListeners();
        return;
      }

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
    final pars = currentParagraphs;

    if (_currentParagraphIndex < pars.length - 1) {
      _currentParagraphIndex++;
      notifyListeners();
    } else if (_currentPageIndex < _pageTexts.length - 1) {
      _currentPageIndex++;
      _currentParagraphIndex = 0;
      notifyListeners();
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
