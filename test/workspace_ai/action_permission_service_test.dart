import 'package:clarix/src/features/workspace/application/action_permission_service.dart';
import 'package:clarix/src/features/workspace/domain/pdf_edit_intent.dart';
import 'package:clarix/src/features/workspace/domain/pdf_page_object.dart';
import 'package:clarix/src/features/workspace/domain/pdf_text_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('askWhenRisky allows replacement but prompts for save', () async {
    final service = ActionPermissionService(
      store: MemoryActionPermissionStore(),
      defaultPolicy: ActionPermissionPolicy.askWhenRisky,
    );
    final replace = _context(
      ReplacePdfTextIntent(
        documentId: 'doc',
        documentRevision: 'rev',
        locator: testLocator,
        range: const PdfTextRange(0, 1),
        replacement: 'b',
        caseMatching: false,
      ),
    );
    expect(await service.authorize(replace), const PermissionAllowed());
    expect(
      await service.authorize(
        _context(
          const SavePdfEditsIntent(documentId: 'doc', documentRevision: 'rev'),
        ),
      ),
      isA<PermissionRequired>(),
    );
  });

  test('persistent workspace grant survives recreation', () async {
    final store = MemoryActionPermissionStore();
    final first = ActionPermissionService(store: store);
    await first.grant(
      policy: ActionPermissionPolicy.allow,
      scope: PermissionScope.workspace,
      workspaceId: 'default',
    );
    final second = ActionPermissionService(store: store);
    expect(await second.policyFor('default'), ActionPermissionPolicy.allow);
  });

  test('native page object rotation is risky and described clearly', () async {
    final service = ActionPermissionService(
      store: MemoryActionPermissionStore(),
      defaultPolicy: ActionPermissionPolicy.askWhenRisky,
    );
    final decision = await service.authorize(
      _context(
        RotatePdfPageObjectIntent(
          documentId: 'doc',
          documentRevision: 'rev',
          locator: testPageObjectLocator,
          radians: 0.2,
        ),
      ),
    );
    expect(decision, isA<PermissionRequired>());
    expect((decision as PermissionRequired).preview, contains('Rotate'));
    expect(decision.risk.reasons, contains('rotates page content'));
  });
}

PermissionContext _context(PdfEditIntent intent) => PermissionContext(
  workspaceId: 'default',
  documentId: 'doc',
  actionName: intent.runtimeType.toString(),
  intent: intent,
);

final testLocator = PdfTextBlockLocator(
  pageNumber: 1,
  objectPath: const <int>[0],
  textDigest: 't',
  geometryDigest: 'g',
  fontFingerprint: 'f',
  sourceRevision: 'rev',
);

final testPageObjectLocator = PdfPageObjectLocator(
  pageNumber: 1,
  objectPath: const <int>[0],
  type: PdfPageObjectType.image,
  contentDigest: 'c',
  geometryDigest: 'g',
  sourceRevision: 'rev',
);
