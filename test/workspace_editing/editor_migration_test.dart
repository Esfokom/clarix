import 'dart:io';
import 'dart:convert';

import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rust editor flag never constructs legacy mutation services', () {
    var legacyControllerCreations = 0;
    final container = ProviderContainer(
      overrides: [
        editingRolloutProvider.overrideWithValue(
          EditingRollout.clarixRustEditingV1,
        ),
        legacyPdfEditingControllerProvider.overrideWith((ref) {
          legacyControllerCreations += 1;
          return PdfEditingController();
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(pdfEditingControllerProvider), isNull);
    expect(legacyControllerCreations, 0);
  });

  test('rollout states keep exactly one gesture authority', () {
    expect(
      EditingRollout.legacy.policy,
      const EditingRolloutPolicy(
        opensRustSession: false,
        constructsLegacyEditor: true,
        rustGesturesEnabled: false,
      ),
    );
    expect(
      EditingRollout.compareScenes.policy,
      const EditingRolloutPolicy(
        opensRustSession: true,
        constructsLegacyEditor: true,
        rustGesturesEnabled: false,
      ),
    );
    expect(
      EditingRollout.clarixRustEditingV1.policy,
      const EditingRolloutPolicy(
        opensRustSession: true,
        constructsLegacyEditor: false,
        rustGesturesEnabled: true,
      ),
    );
  });

  test('scene comparison diagnostics never emit document content', () {
    const secret = 'customer account 4821';
    final diagnostic = compareEditingSceneObjects(
      pageNumber: 3,
      legacy: const <EditingComparisonObject>[
        EditingComparisonObject(
          id: 'legacy-1',
          text: secret,
          left: 10,
          bottom: 20,
          right: 110,
          top: 40,
          capability: 'editable',
        ),
      ],
      rust: const <EditingComparisonObject>[
        EditingComparisonObject(
          id: 'rust-1',
          text: 'different confidential content',
          left: 11,
          bottom: 20,
          right: 110,
          top: 40,
          capability: 'readOnly',
        ),
      ],
    );

    expect(diagnostic.idMismatches, 1);
    expect(diagnostic.boundsMismatches, 1);
    expect(diagnostic.textMismatches, 1);
    expect(diagnostic.capabilityMismatches, 1);
    final encoded = jsonEncode(diagnostic.toContentFreeFields());
    expect(encoded, isNot(contains(secret)));
    expect(encoded, isNot(contains('different confidential content')));
    expect(encoded, isNot(contains('legacy-1')));
    expect(encoded, isNot(contains('rust-1')));
  });

  test('new editing subtree does not import legacy editing authority', () {
    final editingRoot = Directory('lib/src/features/workspace/editing');
    const forbiddenImports = <String>{
      'pdf_edit_session.dart',
      'pdf_native_edit_coordinator.dart',
      'pdf_preview_document_controller.dart',
      'pdf_edit_save_service.dart',
    };

    final violations = <String>[];
    for (final entity in editingRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final contents = entity.readAsStringSync();
      for (final forbidden in forbiddenImports) {
        if (contents.contains(forbidden)) {
          violations.add('${entity.path}: $forbidden');
        }
      }
    }

    expect(violations, isEmpty);
  });
}
