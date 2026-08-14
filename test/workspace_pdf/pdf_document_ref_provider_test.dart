import 'dart:io';
import 'dart:typed_data';

import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test(
    'workspace PDF references read into memory without retaining the file',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'clarix-pdf-ref-',
      );
      final File source = File(
        '${directory.path}${Platform.pathSeparator}source.pdf',
      );
      final File moved = File(
        '${directory.path}${Platform.pathSeparator}moved.pdf',
      );
      await source.writeAsBytes(<int>[1, 2, 3, 4]);
      final ProviderContainer container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await directory.delete(recursive: true);
      });

      final PdfDocumentRef reference = container.read(
        pdfDocumentRefProvider(source.path),
      );
      expect(reference, isA<PdfDocumentRefCustom>());
      final PdfDocumentRefCustom custom = reference as PdfDocumentRefCustom;
      final Uint8List buffer = Uint8List(4);
      expect(await custom.read(buffer, 0, buffer.length), buffer.length);
      expect(buffer, <int>[1, 2, 3, 4]);

      await source.rename(moved.path);
      expect(await moved.exists(), isTrue);
    },
  );
}
