import 'package:flutter_test/flutter_test.dart';
import 'package:clarix/src/core/deep_link_service.dart';

void main() {
  group('DeepLinkService tests', () {
    const service = DeepLinkService();

    test('generates valid clarix:// deep link URI', () {
      final link = service.generateDeepLink(
        filePath: r'C:\Users\user\Documents\sample.pdf',
        page: 42,
        scrollOffset: 0.75,
      );

      expect(link, startsWith('clarix://open?'));
      expect(link, contains('page=42'));
      expect(link, contains('scroll=0.750'));
    });

    test('parses valid deep link URI correctly', () {
      const uriStr = 'clarix://open?path=C%3A%5CUsers%5Cuser%5CDocuments%5Csample.pdf&page=42&scroll=0.750';
      final parsed = service.parseDeepLink(uriStr);

      expect(parsed, isNotNull);
      expect(parsed!.filePath, r'C:\Users\user\Documents\sample.pdf');
      expect(parsed.page, 42);
      expect(parsed.scrollOffset, 0.750);
    });

    test('returns null on invalid or malformed URIs', () {
      expect(service.parseDeepLink(''), isNull);
      expect(service.parseDeepLink('https://google.com'), isNull);
      expect(service.parseDeepLink('clarix://open?path=test.pdf'), isNull);
      expect(service.parseDeepLink('clarix://open?path=test.pdf&page=invalid'), isNull);
    });
  });
}
