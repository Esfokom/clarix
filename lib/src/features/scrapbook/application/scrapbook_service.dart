import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Single clipping item inside the multi-page Scrapbook
class ScrapbookItem {
  const ScrapbookItem({
    required this.id,
    required this.documentTitle,
    required this.filePath,
    required this.pageNumber,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String documentTitle;
  final String filePath;
  final int pageNumber;
  final String text;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'documentTitle': documentTitle,
        'filePath': filePath,
        'pageNumber': pageNumber,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ScrapbookItem.fromJson(Map<String, dynamic> json) {
    return ScrapbookItem(
      id: json['id'] as String,
      documentTitle: json['documentTitle'] as String,
      filePath: json['filePath'] as String,
      pageNumber: json['pageNumber'] as int,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Multi-page Snippet Clipboard Service ("The Scrapbook")
/// Accumulates text clippings across documents and exports to Markdown or HTML.
class ScrapbookService extends ChangeNotifier {
  final List<ScrapbookItem> _items = <ScrapbookItem>[];

  List<ScrapbookItem> get items => List<ScrapbookItem>.unmodifiable(_items);
  int get count => _items.length;

  void addItem({
    required String documentTitle,
    required String filePath,
    required int pageNumber,
    required String text,
  }) {
    if (text.trim().isEmpty) return;
    final item = ScrapbookItem(
      id: 'clip_${DateTime.now().millisecondsSinceEpoch}_${_items.length}',
      documentTitle: documentTitle,
      filePath: filePath,
      pageNumber: pageNumber,
      text: text.trim(),
      timestamp: DateTime.now(),
    );
    _items.insert(0, item);
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    notifyListeners();
  }

  void reorderItems(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    final item = _items.removeAt(oldIndex);
    _items.insert(targetIndex, item);
    notifyListeners();
  }

  /// Exports all collected clippings to clean Markdown text
  String exportToMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Scrapbook Clippings Report')
      ..writeln('Generated on: ${DateTime.now().toLocal()}')
      ..writeln('Total Clippings: ${_items.length}\n')
      ..writeln('---');

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      buffer
        ..writeln('\n### ${i + 1}. ${item.documentTitle} (Page ${item.pageNumber})')
        ..writeln('> ${item.text.replaceAll('\n', '\n> ')}')
        ..writeln('\n*Source: ${item.filePath}*')
        ..writeln('---');
    }
    return buffer.toString();
  }

  /// Exports all collected clippings to a standalone styled HTML file
  String exportToHtml() {
    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html><head><meta charset="utf-8">')
      ..writeln('<title>Scrapbook Clippings Report</title>')
      ..writeln('<style>')
      ..writeln('body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #121214; color: #FAFAFA; padding: 30px; max-width: 800px; margin: auto; }')
      ..writeln('.card { background: #18181B; border: 1px solid #3F3F46; border-radius: 8px; padding: 16px; margin-bottom: 16px; }')
      ..writeln('.meta { font-size: 12px; color: #A1A1AA; font-weight: bold; margin-bottom: 8px; }')
      ..writeln('blockquote { border-left: 3px solid #6366F1; margin: 0; padding-left: 12px; font-size: 14px; line-height: 1.5; color: #E4E4E7; }')
      ..writeln('</style></head><body>')
      ..writeln('<h1>✂️ Scrapbook Clippings Report</h1>')
      ..writeln('<p style="color:#A1A1AA;">Total Clippings: ${_items.length}</p>');

    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final escapedText = const HtmlEscape().convert(item.text);
      final escapedTitle = const HtmlEscape().convert(item.documentTitle);
      buffer
        ..writeln('<div class="card">')
        ..writeln('  <div class="meta">#${i + 1} • $escapedTitle • Page ${item.pageNumber}</div>')
        ..writeln('  <blockquote>$escapedText</blockquote>')
        ..writeln('</div>');
    }

    buffer.writeln('</body></html>');
    return buffer.toString();
  }
}
