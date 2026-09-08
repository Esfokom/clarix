part of 'reader_viewer_pane.dart';

/// One narratable sentence on a page: its plain text plus the PDF-space
/// rects (one per line it spans) used both to paint its highlight and to
/// hit-test clicks against it.
class _PageSentence {
  const _PageSentence({required this.segment, required this.pdfRects});

  final ReadAloudSegment segment;
  final List<PdfRect> pdfRects;
}

/// Splits page text into sentence-ish spans on `.`/`!`/`?` followed by
/// whitespace and a capital/opening character. Heuristic, not grammatical —
/// good enough to keep read-aloud chunks short enough to synthesize quickly
/// and to highlight at a granularity close to what Chrome's Read Aloud does.
List<({int start, int end})> _splitSentences(String text) {
  if (text.trim().isEmpty) return const <({int start, int end})>[];
  final RegExp boundary = RegExp(r'''(?<=[.!?])\s+(?=[A-Z0-9"‘“(])''');
  final List<({int start, int end})> ranges = <({int start, int end})>[];
  int start = 0;
  for (final RegExpMatch match in boundary.allMatches(text)) {
    ranges.add((start: start, end: match.start));
    start = match.end;
  }
  if (start < text.length) {
    ranges.add((start: start, end: text.length));
  }
  return ranges;
}

extension _ReaderReadAloud on _PdfViewerPaneState {
  Future<List<_PageSentence>> _ensurePageSentences(int pageNumber) async {
    final List<_PageSentence>? cached = _pageSentenceCache[pageNumber];
    if (cached != null) return cached;
    if (!_controller.isReady) return const <_PageSentence>[];
    final List<PdfPage> pages = _controller.pages;
    if (pageNumber < 1 || pageNumber > pages.length) {
      return const <_PageSentence>[];
    }

    final PdfPage page = pages[pageNumber - 1];
    final PdfPageText pageText = await page.loadStructuredText();
    final List<_PageSentence> sentences = <_PageSentence>[];
    int order = 0;
    for (final ({int start, int end}) range in _splitSentences(
      pageText.fullText,
    )) {
      final String text = pageText.fullText
          .substring(range.start, range.end)
          .trim();
      if (text.isEmpty) continue;
      final PdfPageTextRange pdfRange = pageText.getRangeFromAB(
        range.start,
        range.end - 1,
      );
      final List<PdfRect> rects = pdfRange
          .enumerateFragmentBoundingRects()
          .map((PdfTextFragmentBoundingRect r) => r.bounds)
          // ignore: prefer_is_not_empty
          .where((PdfRect r) => !r.isEmpty)
          .toList(growable: false);
      if (rects.isEmpty) continue;
      sentences.add(
        _PageSentence(
          segment: ReadAloudSegment(
            id: '$pageNumber:${order++}',
            text: text,
            pageNumber: pageNumber,
          ),
          pdfRects: rects,
        ),
      );
    }

    if (mounted) {
      _pageSentenceCache[pageNumber] = sentences;
      _updateState();
    }
    return sentences;
  }

  void _precachePageSentences(int pageNumber) {
    if (_pageSentenceCache.containsKey(pageNumber)) return;
    unawaited(_ensurePageSentences(pageNumber));
  }

  void _paintReadAloudHighlight(Canvas canvas, Rect pageRect, PdfPage page) {
    final List<_PageSentence>? sentences = _pageSentenceCache[page.pageNumber];
    if (sentences == null || sentences.isEmpty) return;

    final TtsPlaybackState playback =
        ref.read(ttsNotifierProvider).value?.playback ??
        const TtsPlaybackState();
    final String? speakingId = playback.status == TtsPlaybackStatus.idle
        ? null
        : playback.currentSegmentId;

    final Paint paint = Paint()
      ..color = widget.colors.accent.withValues(alpha: 0.28);
    for (final _PageSentence sentence in sentences) {
      final List<Rect> viewRects = sentence.pdfRects
          .map(
            (PdfRect r) => r
                .toRect(page: page, scaledPageSize: pageRect.size)
                .translate(pageRect.left, pageRect.top),
          )
          .toList(growable: false);
      if (viewRects.isEmpty) continue;
      Rect union = viewRects.first;
      for (final Rect r in viewRects.skip(1)) {
        union = union.expandToInclude(r);
      }
      _readAloudHitAreas[sentence.segment.id] = union;
      if (sentence.segment.id == speakingId) {
        for (final Rect r in viewRects) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(2)),
            paint,
          );
        }
      }
    }
  }

  String? _readAloudSegmentIdAt(Offset documentPosition) {
    for (final MapEntry<String, Rect> entry in _readAloudHitAreas.entries) {
      if (entry.value.inflate(2).contains(documentPosition)) return entry.key;
    }
    return null;
  }

  Future<void> _startReadAloud(Offset localAnchor) async {
    if (!_controller.isReady) return;
    final Offset documentPosition = _controller.localToDocument(localAnchor);
    final int currentPage = _page;

    final List<_PageSentence> currentSentences = await _ensurePageSentences(
      currentPage,
    );
    if (currentSentences.isEmpty) return;

    int startIndex = 0;
    final String? tappedId = _readAloudSegmentIdAt(documentPosition);
    if (tappedId != null) {
      final int found = currentSentences.indexWhere(
        (_PageSentence s) => s.segment.id == tappedId,
      );
      if (found >= 0) startIndex = found;
    }

    final List<ReadAloudSegment> initial = currentSentences
        .sublist(startIndex)
        .map((_PageSentence s) => s.segment)
        .toList(growable: false);

    _readAloudSessionSegments
      ..clear()
      ..addAll(initial);

    _readAloudSessionOwned = true;
    await ref
        .read(ttsNotifierProvider.notifier)
        .startReading(
          documentId: widget.tab.documentId,
          segments: initial,
          startIndex: 0,
        );

    final int? pageCount = widget.tab.pageCountHint;
    final int next = currentPage + 1;
    if (pageCount == null || next > pageCount) {
      _readAloudNextPageToExtract = null;
      ref.read(ttsNotifierProvider.notifier).finishSegments();
    } else {
      _readAloudNextPageToExtract = next;
      unawaited(_extendReadAloudIfNeeded());
    }
  }

  Future<void> _startReadAloudFromCurrentPage() async {
    if (!_controller.isReady) return;
    final int currentPage = _page;

    final List<_PageSentence> currentSentences = await _ensurePageSentences(
      currentPage,
    );
    if (currentSentences.isEmpty) return;

    final List<ReadAloudSegment> initial = currentSentences
        .map((_PageSentence s) => s.segment)
        .toList(growable: false);

    _readAloudSessionSegments
      ..clear()
      ..addAll(initial);

    _readAloudSessionOwned = true;
    await ref
        .read(ttsNotifierProvider.notifier)
        .startReading(
          documentId: widget.tab.documentId,
          segments: initial,
          startIndex: 0,
        );

    final int? pageCount = widget.tab.pageCountHint;
    final int next = currentPage + 1;
    if (pageCount == null || next > pageCount) {
      _readAloudNextPageToExtract = null;
      ref.read(ttsNotifierProvider.notifier).finishSegments();
    } else {
      _readAloudNextPageToExtract = next;
      unawaited(_extendReadAloudIfNeeded());
    }
  }

  bool _handleReadAloudSkipTap(Offset documentPosition) {
    final TtsPlaybackState playback =
        ref.read(ttsNotifierProvider).value?.playback ??
        const TtsPlaybackState();
    if (playback.status == TtsPlaybackStatus.idle) return false;
    final String? id = _readAloudSegmentIdAt(documentPosition);
    if (id == null) return false;
    final int index = _readAloudSessionSegments.indexWhere(
      (ReadAloudSegment s) => s.id == id,
    );
    if (index < 0) return false;
    ref.read(ttsNotifierProvider.notifier).skipToIndex(index);
    return true;
  }

  void _onReadAloudPlaybackChanged(
    TtsPlaybackState? previous,
    TtsPlaybackState next,
  ) {
    if (!mounted) return;
    if (next.documentId != widget.tab.documentId &&
        next.status != TtsPlaybackStatus.idle) {
      return;
    }
    if (next.currentSegmentId != previous?.currentSegmentId) {
      if (_controller.isReady) _controller.invalidate();
    }
    if (next.status == TtsPlaybackStatus.idle) {
      _readAloudNextPageToExtract = null;
      _readAloudSessionOwned = false;
      return;
    }
    if (next.currentPage != null &&
        next.currentPage != _page &&
        _controller.isReady) {
      unawaited(_controller.goToPage(pageNumber: next.currentPage!));
    }
    if (_readAloudNextPageToExtract != null &&
        next.segmentTotal - next.segmentIndex <= 2) {
      unawaited(_extendReadAloudIfNeeded());
    }
  }

  Future<void> _extendReadAloudIfNeeded() async {
    if (_readAloudExtending) return;
    final int? nextPage = _readAloudNextPageToExtract;
    if (nextPage == null) return;
    final int? pageCount = widget.tab.pageCountHint;
    if (pageCount == null) return;

    _readAloudExtending = true;
    try {
      final List<_PageSentence> sentences = await _ensurePageSentences(
        nextPage,
      );
      final List<ReadAloudSegment> segments = sentences
          .map((_PageSentence s) => s.segment)
          .toList(growable: false);
      _readAloudSessionSegments.addAll(segments);
      if (segments.isNotEmpty) {
        ref.read(ttsNotifierProvider.notifier).appendSegments(segments);
      }
      final int next = nextPage + 1;
      if (next > pageCount) {
        _readAloudNextPageToExtract = null;
        ref.read(ttsNotifierProvider.notifier).finishSegments();
      } else {
        _readAloudNextPageToExtract = next;
      }
    } finally {
      _readAloudExtending = false;
    }
  }

  void _resetReadAloudSession() {
    _readAloudNextPageToExtract = null;
    _readAloudSessionSegments.clear();
    if (_readAloudSessionOwned) {
      _readAloudSessionOwned = false;
      unawaited(ref.read(ttsNotifierProvider.notifier).stop());
    }
  }
}

class _ReadAloudBar extends StatelessWidget {
  const _ReadAloudBar({
    required this.playback,
    required this.colors,
    required this.onPauseResume,
    required this.onStop,
  });

  final TtsPlaybackState playback;
  final WorkspaceSurfaceTokens colors;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final bool preparing = playback.status == TtsPlaybackStatus.preparing;
    final bool speaking = playback.status == TtsPlaybackStatus.speaking;
    return Material(
      color: colors.panelRaised,
      elevation: 6,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(LucideIcons.headphones, size: 16, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              preparing
                  ? 'Preparing…'
                  : 'Reading page ${playback.currentPage ?? '—'}',
              style: TextStyle(color: colors.textStrong, fontSize: 12),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 28,
              height: 28,
              child: preparing
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      tooltip: speaking ? 'Pause' : 'Resume',
                      onPressed: onPauseResume,
                      icon: Icon(speaking ? Icons.pause : Icons.play_arrow),
                    ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: 'Stop reading',
              onPressed: onStop,
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
      ),
    );
  }
}
