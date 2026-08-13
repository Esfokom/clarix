import 'dart:convert';

import 'package:clarix/src/features/workspace/application/action_permission_service.dart';
import 'package:clarix/src/features/workspace/application/ai_tool_registry.dart';
import 'package:clarix/src/features/workspace/application/pdf_editing_controller.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_session.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:clarix/src/features/workspace/infrastructure/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes nine strict PDF editing tool schemas', () {
    final registry = _registry();
    expect(registry.schemas, hasLength(9));
    expect(
      registry.schemas.every(
        (schema) =>
            ((schema['function'] as Map)['parameters']
                as Map)['additionalProperties'] ==
            false,
      ),
      isTrue,
    );
  });

  test(
    'agent replacement shares dispatcher state and rejects unknown keys',
    () async {
      final registry = _registry();
      final locator = _block().locator;
      final result = await registry.execute(
        AiToolCall(
          id: 'call',
          name: 'replace_pdf_text',
          argumentsJson: jsonEncode(<String, Object?>{
            'documentId': 'doc',
            'documentRevision': 'rev',
            'locator': _locatorJson(locator),
            'start': 0,
            'end': 3,
            'replacement': 'New',
            'caseMatching': false,
          }),
        ),
        allowedDocumentIds: const <String>{'doc'},
      );
      expect(result['error'], isNull);
      final session = registry.editing.sessionsByTabId['tab']!;
      expect(session.blocks.single.text, 'New');
      expect(session.commands.single.provenance.name, 'agent');

      final invalid = await registry.execute(
        const AiToolCall(
          id: 'bad',
          name: 'undo_pdf_edit',
          argumentsJson:
              '{"documentId":"doc","documentRevision":"rev","extra":1}',
        ),
        allowedDocumentIds: const <String>{'doc'},
      );
      expect((invalid['error'] as Map)['code'], 'invalid_arguments');
    },
  );
}

AiToolRegistry _registry() {
  final editing = PdfEditingController(commandId: () => 'agent-command')
    ..registerSession(
      'tab',
      PdfEditingSession.empty(
        'doc',
        sourceRevision: 'rev',
      ).withBlocks(<PdfTextBlock>[_block()]),
    );
  return AiToolRegistry(
    editing: editing,
    permissions: ActionPermissionService(
      store: MemoryActionPermissionStore(),
      defaultPolicy: ActionPermissionPolicy.allow,
    ),
    pathForDocument: (_) => null,
  );
}

PdfTextBlock _block() {
  const style = PdfTextStyle(
    fontFamily: 'Arial',
    fontSize: 12,
    fillColorValue: 0xff000000,
    fontWeight: 400,
    italic: false,
    underline: false,
    baselineShift: 0,
    alignment: PdfTextAlignment.left,
    characterSpacing: 0,
    lineSpacing: 0,
    horizontalScaling: 1,
  );
  return PdfTextBlock(
    locator: PdfTextBlockLocator(
      pageNumber: 1,
      objectPath: const <int>[0],
      textDigest: 't',
      geometryDigest: 'g',
      fontFingerprint: 'f',
      sourceRevision: 'rev',
    ),
    text: 'Old',
    originalText: 'Old',
    runs: const <PdfTextRun>[
      PdfTextRun(range: PdfTextRange(0, 3), style: style),
    ],
    bounds: const PdfBox(0, 0, 100, 20),
    transform: const PdfTransform(1, 0, 0, 1, 0, 12),
    baseline: 12,
    writingDirection: PdfWritingDirection.leftToRight,
    capabilities: PdfTextCapability.values,
    readOnlyReason: null,
  );
}

Map<String, Object?> _locatorJson(PdfTextBlockLocator locator) =>
    <String, Object?>{
      'pageNumber': locator.pageNumber,
      'objectPath': locator.objectPath,
      'textDigest': locator.textDigest,
      'geometryDigest': locator.geometryDigest,
      'fontFingerprint': locator.fontFingerprint,
      'sourceRevision': locator.sourceRevision,
    };
