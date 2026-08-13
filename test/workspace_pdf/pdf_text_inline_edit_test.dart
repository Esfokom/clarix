import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text delta isolates the smallest UTF-16 replacement', () {
    final delta = PdfTextDelta.between('Quarterly Revenue', 'Quarterly Income');

    expect(delta.replacedRange, const PdfTextRange(10, 16));
    expect(delta.replacedText, 'Revenu');
    expect(delta.insertedText, 'Incom');
  });
}
