import 'package:clarix/src/features/pdf_editor/domain/pdf_text_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final sample in <(String, String, String)>[
    ('TOTAL REVENUE', 'net income', 'NET INCOME'),
    ('total revenue', 'Net Income', 'net income'),
    ('Total Revenue', 'net income', 'Net Income'),
    ('Total revenue', 'net income', 'Net income'),
    ('iPhone Revenue', 'net income', 'net income'),
  ]) {
    test('matches ${sample.$1}', () {
      expect(matchReplacementCase(sample.$1, sample.$2), sample.$3);
    });
  }

  test('keeps punctuation while matching sentence case', () {
    expect(
      matchReplacementCase('Total revenue.', 'NET INCOME!'),
      'Net income!',
    );
  });
}
