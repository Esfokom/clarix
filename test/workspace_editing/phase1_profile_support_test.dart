import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/phase1_profile_support.dart';

void main() {
  test(
    'large profile corpus has a valid xref for every generated object',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'clarix-profile-support-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await writeBlankPdfCorpus(directory, 3);
      final bytes = await file.readAsBytes();
      final source = latin1.decode(bytes);

      expect(RegExp(r'/Type /Page ').allMatches(source).length, 3);
      final startXref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(source)!.group(1)!,
      );
      expect(source.substring(startXref).startsWith('xref\n'), isTrue);

      final xrefLines = source.substring(startXref).split('\n');
      final objectCount = int.parse(xrefLines[1].split(' ').last) - 1;
      for (var id = 1; id <= objectCount; id++) {
        final offset = int.parse(xrefLines[id + 2].substring(0, 10));
        expect(source.substring(offset).startsWith('$id 0 obj\n'), isTrue);
      }
    },
  );

  test('profile percentile is deterministic and empty-safe', () {
    expect(percentile95(<int>[]), 0);
    expect(percentile95(List<int>.generate(100, (index) => index + 1)), 95);
  });
}
