import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../application/offline_audio_book_service.dart';

class AudioBookPlayerBar extends StatelessWidget {
  const AudioBookPlayerBar({
    super.key,
    required this.audioBookService,
  });

  final OfflineAudioBookService audioBookService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: audioBookService,
      builder: (context, _) {
        final isPlaying = audioBookService.isPlaying;
        final currentPage = audioBookService.currentPageIndex + 1;
        final totalPages = audioBookService.totalPages;
        final progress = audioBookService.progressPercentage;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xEE0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x3364748B)),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.headphones, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline Audio-Book Mode • Page $currentPage of $totalPages',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          audioBookService.currentParagraph.isEmpty
                              ? 'Press play to start reading document.'
                              : audioBookService.currentParagraph,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Speed Toggle Chip
                  PopupMenuButton<double>(
                    initialValue: audioBookService.playbackSpeed,
                    tooltip: 'Playback Speed',
                    onSelected: (speed) => audioBookService.setPlaybackSpeed(speed),
                    itemBuilder: (context) => [0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                      return PopupMenuItem<double>(
                        value: s,
                        child: Text('${s}x Speed', style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x331E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x3364748B)),
                      ),
                      child: Text(
                        '${audioBookService.playbackSpeed}x',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(LucideIcons.skipBack, size: 14, color: Colors.white70),
                    onPressed: () => audioBookService.previousPage(),
                  ),
                  IconButton.filled(
                    onPressed: () {
                      if (isPlaying) {
                        audioBookService.pause();
                      } else {
                        audioBookService.play();
                      }
                    },
                    icon: Icon(isPlaying ? LucideIcons.pause : LucideIcons.play, size: 16),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.skipForward, size: 14, color: Colors.white70),
                    onPressed: () => audioBookService.nextPage(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0x331E293B),
                color: const Color(0xFF10B981),
                minHeight: 3,
              ),
            ],
          ),
        );
      },
    );
  }
}
