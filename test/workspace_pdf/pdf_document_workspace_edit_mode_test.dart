import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/document_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pdfrx reader selection is disabled while Clarix owns edit gestures',
    () {
      expect(
        textSelectionParamsFor(PdfEditingInteraction.reading).enabled,
        isTrue,
      );
      expect(
        textSelectionParamsFor(PdfEditingInteraction.objectSelected).enabled,
        isFalse,
      );
      expect(
        textSelectionParamsFor(PdfEditingInteraction.textEditing).enabled,
        isFalse,
      );
    },
  );
}
