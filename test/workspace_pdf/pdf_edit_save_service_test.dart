import 'dart:io';

import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/pdf_edit_save_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pdf_text_fixture.dart';

void main() {
  test('validation failure leaves original bytes unchanged', () async {
    final file = await PdfTextFixture.singleBlock('Original');
    addTearDown(() => file.parent.delete(recursive: true));
    final before = await file.readAsBytes();
    final service = PdfEditSaveService(
      writeDraft: (_, _) async {},
      validate: (_) async => throw const PdfValidationFailure('forced'),
    );

    await expectLater(
      service.save(
        PdfSaveRequest(
          path: file.path,
          sourceRevision: await sha256File(file),
          draft: PdfEditingSession.empty(
            'doc',
            sourceRevision: await sha256File(file),
          ),
        ),
      ),
      throwsA(isA<PdfValidationFailure>()),
    );
    expect(await file.readAsBytes(), before);
    expect(
      file.parent.listSync().whereType<File>().where(
        (item) => item.path.contains('clarix-edit'),
      ),
      isEmpty,
    );
  });

  test(
    'rejects an externally changed source before creating a draft',
    () async {
      final file = await PdfTextFixture.singleBlock('Original');
      addTearDown(() => file.parent.delete(recursive: true));
      final service = PdfEditSaveService(writeDraft: (_, _) async {});

      await expectLater(
        service.save(
          PdfSaveRequest(
            path: file.path,
            sourceRevision: 'stale',
            draft: PdfEditingSession.empty('doc', sourceRevision: 'stale'),
          ),
        ),
        throwsA(isA<PdfExternalRevisionFailure>()),
      );
    },
  );
}
