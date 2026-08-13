import 'package:clarix/src/features/workspace/application/workspace_notifier.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('external revision offers reload and save a copy', () {
    final presentation = presentPdfFailure(
      const PdfExternalRevisionFailure(expected: 'a', actual: 'b'),
    );
    expect(presentation.message, 'The PDF changed outside Clarix.');
    expect(presentation.actions, <PdfRecoveryAction>[
      PdfRecoveryAction.reload,
      PdfRecoveryAction.saveCopy,
    ]);
  });

  test('access denied keeps draft and offers save a copy', () {
    final presentation = presentPdfFailure(
      const PdfAtomicReplacementFailure('Access is denied.'),
    );
    expect(presentation.message, contains('draft is still available'));
    expect(presentation.actions, contains(PdfRecoveryAction.saveCopy));
  });
}
