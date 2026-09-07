import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:clarix/src/features/scrapbook/application/scrapbook_service.dart';

final scrapbookServiceProvider = Provider<ScrapbookService>((ref) {
  return ScrapbookService();
});

class ScrapbookSidePane extends ConsumerWidget {
  const ScrapbookSidePane({
    this.onJumpToClipping,
    super.key,
  });

  final ValueChanged<ScrapbookItem>? onJumpToClipping;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrapbook = ref.watch(scrapbookServiceProvider);

    return ListenableBuilder(
      listenable: scrapbook,
      builder: (context, _) {
        final items = scrapbook.items;

        return Container(
          color: const Color(0xFF18181B),
          child: Column(
            children: [
              // Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF27272A),
                  border: Border(bottom: BorderSide(color: Color(0xFF3F3F46))),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.scissors, size: 16, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Scrapbook Clippings',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F3F46),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${scrapbook.count}',
                        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Export Scrapbook to Markdown / HTML',
                      child: PopupMenuButton<String>(
                        icon: const Icon(LucideIcons.download, size: 15, color: Color(0xFFA1A1AA)),
                        onSelected: (choice) => _exportScrapbook(context, scrapbook, choice),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'md', child: Text('Export as Markdown (.md)', style: TextStyle(fontSize: 11))),
                          PopupMenuItem(value: 'html', child: Text('Export as HTML (.html)', style: TextStyle(fontSize: 11))),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: 'Clear all clippings',
                      child: IconButton(
                        icon: const Icon(LucideIcons.trash2, size: 15, color: Color(0xFFA1A1AA)),
                        onPressed: items.isEmpty ? null : () => scrapbook.clearAll(),
                      ),
                    ),
                  ],
                ),
              ),

              // Items List Area
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.scissors, size: 32, color: Colors.white24),
                            SizedBox(height: 8),
                            Text('No clippings in Scrapbook', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            SizedBox(height: 4),
                            Text(
                              'Select text in PDF viewer & click "Send to Scrapbook"',
                              style: TextStyle(color: Colors.white38, fontSize: 10.5),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: items.length,
                        onReorderItem: (oldIdx, newIdx) => scrapbook.reorderItems(oldIdx, newIdx),
                        itemBuilder: (ctx, index) {
                          final item = items[index];
                          return Container(
                            key: ValueKey(item.id),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF242427),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF3F3F46)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(LucideIcons.fileText, size: 12, color: Color(0xFFA1A1AA)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: InkWell(
                                        onTap: onJumpToClipping != null
                                            ? () => onJumpToClipping!(item)
                                            : null,
                                        child: Text(
                                          '${item.documentTitle} • p.${item.pageNumber}',
                                          style: const TextStyle(
                                            color: Color(0xFFFAFAFA),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            decoration: TextDecoration.underline,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    if (onJumpToClipping != null)
                                      Tooltip(
                                        message: 'Jump to PDF Page ${item.pageNumber}',
                                        child: IconButton(
                                          icon: const Icon(LucideIcons.externalLink, size: 12, color: Color(0xFFA1A1AA)),
                                          onPressed: () => onJumpToClipping!(item),
                                        ),
                                      ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.copy, size: 12, color: Color(0xFFA1A1AA)),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: item.text));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Clipping copied to clipboard!'), duration: Duration(seconds: 1)),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.x, size: 12, color: Color(0xFFA1A1AA)),
                                      onPressed: () => scrapbook.removeItem(item.id),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  item.text,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                                  maxLines: 6,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportScrapbook(BuildContext context, ScrapbookService scrapbook, String format) async {
    if (scrapbook.count == 0) return;
    final content = format == 'md' ? scrapbook.exportToMarkdown() : scrapbook.exportToHtml();
    final ext = format == 'md' ? 'md' : 'html';

    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export Scrapbook Clippings',
      fileName: 'scrapbook_report.$ext',
      type: FileType.custom,
      allowedExtensions: [ext],
    );

    if (savePath != null) {
      final file = File(savePath);
      await file.writeAsString(content);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported Scrapbook report to ${file.path}')),
        );
      }
    }
  }
}
