import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  test('installs encoded live bytes without replaying a draft', () async {
    final directory = await Directory.systemTemp.createTemp('clarix-save');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}document.pdf');
    await file.writeAsBytes(<int>[1, 2, 3]);
    final revision = sha256.convert(await file.readAsBytes()).toString();
    var released = false;
    final service = PdfEditSaveService(
      writeDraft: (_, _) => throw StateError('draft replay must not run'),
    );

    final outcome = await service.saveEncoded(
      path: file.path,
      sourceRevision: revision,
      encodedPdf: Uint8List.fromList(<int>[9, 8, 7]),
      beforeReplace: () async => released = true,
    );

    expect(released, isTrue);
    expect(await file.readAsBytes(), <int>[9, 8, 7]);
    expect(outcome.newRevision, sha256.convert(<int>[9, 8, 7]).toString());
  });
}
