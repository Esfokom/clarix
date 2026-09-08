import 'package:clarix/src/features/pdf_editor/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/reader/presentation/reader_viewer_pane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

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
        isTrue,
      );
      expect(
        textSelectionParamsFor(PdfEditingInteraction.textEditing).enabled,
        isFalse,
      );
    },
  );

  test('pdfrx page navigation keys are consumed during text editing', () {
    expect(
      viewerKeyHandlerFor(PdfEditingInteraction.textEditing)(
        const PdfViewerKeyHandlerParams(),
        LogicalKeyboardKey.space,
        true,
      ),
      isTrue,
    );
    expect(
      viewerKeyHandlerFor(PdfEditingInteraction.reading)(
        const PdfViewerKeyHandlerParams(),
        LogicalKeyboardKey.space,
        true,
      ),
      isNull,
    );
  });
}
