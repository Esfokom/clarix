import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Dart and PDFium editing authorities are deleted', () {
    const deleted = <String>[
      'lib/src/features/workspace/application/pdf_editing_controller.dart',
      'lib/src/features/workspace/application/pdf_edit_intent_dispatcher.dart',
      'lib/src/features/workspace/infrastructure/pdf_native_edit_coordinator.dart',
      'lib/src/features/workspace/infrastructure/pdf_preview_document_controller.dart',
      'lib/src/features/workspace/infrastructure/pdf_edit_save_service.dart',
    ];

    expect(
      deleted.where((path) => File(path).existsSync()),
      isEmpty,
      reason: 'The Rust editor must be the only mutation authority.',
    );
  });

  test('workspace wiring has no legacy editing fallback', () {
    const roots = <String>[
      'integration_test',
      'lib/src/features/workspace/application',
      'lib/src/features/workspace/presentation',
      'lib/src/features/workspace/editing',
    ];
    const forbidden = <String>[
      'legacyPdfEditingControllerProvider',
      'pdfEditingControllerProvider',
      'EditingRollout.legacy',
      'EditingRollout.compareScenes',
      'pdf_native_edit_coordinator.dart',
      'pdf_preview_document_controller.dart',
      'pdf_edit_save_service.dart',
    ];
    final violations = <String>[];

    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final contents = entity.readAsStringSync();
        for (final token in forbidden) {
          if (contents.contains(token)) {
            violations.add('${entity.path}: $token');
          }
        }
      }
    }

    expect(violations, isEmpty);
  });

  test('AI mutation remains deferred until the Rust authority is exposed', () {
    final registry = File(
      'lib/src/features/workspace/application/ai_tool_registry.dart',
    ).readAsStringSync();
    expect(registry, contains('static const Set<String> names = <String>{}'));
    expect(registry, isNot(contains('PdfEditingController')));
  });
}
