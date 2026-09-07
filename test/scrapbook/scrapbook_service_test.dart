import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/features/scrapbook/application/scrapbook_service.dart';

void main() {
  group('ScrapbookService tests', () {
    test('adds, reorders, and removes clippings cleanly', () {
      final service = ScrapbookService();

      service.addItem(
        documentTitle: 'Doc A',
        filePath: r'C:\docs\a.pdf',
        pageNumber: 1,
        text: 'First clipping content',
      );
      service.addItem(
        documentTitle: 'Doc B',
        filePath: r'C:\docs\b.pdf',
        pageNumber: 5,
        text: 'Second clipping content',
      );

      expect(service.count, 2);
      expect(service.items.first.documentTitle, 'Doc B');

      service.reorderItems(0, 2);
      expect(service.items.first.documentTitle, 'Doc A');

      service.removeItem(service.items.first.id);
      expect(service.count, 1);

      service.clearAll();
      expect(service.count, 0);
    });

    test('exports clippings to Markdown and HTML cleanly', () {
      final service = ScrapbookService();
      service.addItem(
        documentTitle: 'Sample PDF',
        filePath: r'C:\docs\sample.pdf',
        pageNumber: 12,
        text: 'Key research paragraph excerpt.',
      );

      final md = service.exportToMarkdown();
      expect(md, contains('# Scrapbook Clippings Report'));
      expect(md, contains('Sample PDF'));
      expect(md, contains('Key research paragraph excerpt.'));

      final html = service.exportToHtml();
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Key research paragraph excerpt.'));
    });
  });
}
