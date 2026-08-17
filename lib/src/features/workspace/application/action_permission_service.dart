import 'package:shared_preferences/shared_preferences.dart';

import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';

enum ActionPermissionPolicy { allow, askWhenRisky, askAlways }

enum PermissionScope { action, document, session, workspace }

final class PdfEditRiskAssessment {
  PdfEditRiskAssessment({required this.risky, required List<String> reasons})
    : reasons = List<String>.unmodifiable(reasons);
  final bool risky;
  final List<String> reasons;
}

final class PermissionContext {
  const PermissionContext({
    required this.workspaceId,
    required this.documentId,
    required this.actionName,
    required this.intent,
  });
  final String workspaceId;
  final String documentId;
  final String actionName;
  final PdfEditIntent intent;
}

sealed class PermissionDecision {
  const PermissionDecision();
  Map<String, Object?> toJson();
}

final class PermissionAllowed extends PermissionDecision {
  const PermissionAllowed();
  @override
  Map<String, Object?> toJson() => const <String, Object?>{
    'permission': 'allowed',
  };
  @override
  bool operator ==(Object other) => other is PermissionAllowed;
  @override
  int get hashCode => 1;
}

final class PermissionRequired extends PermissionDecision {
  PermissionRequired({
    required this.context,
    required this.risk,
    required this.preview,
  });
  final PermissionContext context;
  final PdfEditRiskAssessment risk;
  final String preview;
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'permission': 'required',
    'action': context.actionName,
    'documentId': context.documentId,
    'risky': risk.risky,
    'reasons': risk.reasons,
    'preview': preview,
  };
}

abstract interface class ActionPermissionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

final class SharedPreferencesActionPermissionStore
    implements ActionPermissionStore {
  const SharedPreferencesActionPermissionStore(this.preferences);
  final SharedPreferencesAsync preferences;
  @override
  Future<String?> read(String key) => preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      preferences.setString(key, value);
}

final class MemoryActionPermissionStore implements ActionPermissionStore {
  final Map<String, String> _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

final class ActionPermissionService {
  ActionPermissionService({
    required this.store,
    this.defaultPolicy = ActionPermissionPolicy.askAlways,
  });

  final ActionPermissionStore store;
  final ActionPermissionPolicy defaultPolicy;
  final Map<String, ActionPermissionPolicy> _memoryGrants =
      <String, ActionPermissionPolicy>{};

  Future<ActionPermissionPolicy> policyFor(String workspaceId) async {
    final value = await store.read(_workspaceKey(workspaceId));
    return value == null
        ? defaultPolicy
        : ActionPermissionPolicy.values.byName(value);
  }

  Future<void> grant({
    required ActionPermissionPolicy policy,
    required PermissionScope scope,
    required String workspaceId,
    String? documentId,
    String? actionName,
  }) async {
    if (scope == PermissionScope.workspace) {
      await store.write(_workspaceKey(workspaceId), policy.name);
      return;
    }
    _memoryGrants[_grantKey(scope, workspaceId, documentId, actionName)] =
        policy;
  }

  Future<PermissionDecision> authorize(PermissionContext context) async {
    final policy =
        _effectiveMemoryPolicy(context) ?? await policyFor(context.workspaceId);
    if (policy == ActionPermissionPolicy.allow) {
      return const PermissionAllowed();
    }
    final risk = classifyPdfEditRisk(context.intent);
    if (policy == ActionPermissionPolicy.askWhenRisky && !risk.risky) {
      return const PermissionAllowed();
    }
    return PermissionRequired(
      context: context,
      risk: risk,
      preview: _preview(context.intent),
    );
  }

  ActionPermissionPolicy? _effectiveMemoryPolicy(PermissionContext context) {
    for (final key in <String>[
      _grantKey(
        PermissionScope.action,
        context.workspaceId,
        context.documentId,
        context.actionName,
      ),
      _grantKey(
        PermissionScope.document,
        context.workspaceId,
        context.documentId,
        null,
      ),
      _grantKey(PermissionScope.session, context.workspaceId, null, null),
    ]) {
      if (_memoryGrants[key] case final policy?) return policy;
    }
    return null;
  }
}

PdfEditRiskAssessment classifyPdfEditRisk(PdfEditIntent intent) {
  final reasons = <String>[];
  if (intent is SavePdfEditsIntent) reasons.add('writes the PDF file');
  if (intent is MovePdfTextBlockIntent) reasons.add('moves page content');
  if (intent is MovePdfPageObjectIntent) reasons.add('moves page content');
  if (intent is ResizePdfPageObjectIntent) reasons.add('resizes page content');
  if (intent is RotatePdfPageObjectIntent) reasons.add('rotates page content');
  if (intent.editCount > 10) reasons.add('changes more than ten objects');
  if (intent is ReplacePdfTextIntent &&
      intent.range.length > 0 &&
      intent.replacement.length / intent.range.length < 0.75) {
    reasons.add('deletes at least 25% of the selected text');
  }
  return PdfEditRiskAssessment(risky: reasons.isNotEmpty, reasons: reasons);
}

String _preview(PdfEditIntent intent) => switch (intent) {
  ReplacePdfTextIntent(:final replacement) =>
    'Replace selected PDF text with “$replacement”.',
  FormatPdfTextIntent() => 'Change PDF text formatting.',
  MovePdfTextBlockIntent() => 'Move a PDF text block.',
  ResizePdfTextBlockIntent() => 'Resize a PDF text block.',
  MovePdfPageObjectIntent() => 'Move a native PDF page object.',
  ResizePdfPageObjectIntent() => 'Resize a native PDF page object.',
  RotatePdfPageObjectIntent() => 'Rotate native PDF page content.',
  SavePdfEditsIntent() => 'Save edits to the PDF file.',
  UndoPdfEditIntent() => 'Undo the latest PDF edit.',
  RedoPdfEditIntent() => 'Redo the latest PDF edit.',
  _ => 'Apply a PDF edit.',
};

String _workspaceKey(String workspaceId) =>
    'pdf_edit_permission.workspace.$workspaceId';

String _grantKey(
  PermissionScope scope,
  String workspaceId,
  String? documentId,
  String? actionName,
) => '${scope.name}|$workspaceId|${documentId ?? '*'}|${actionName ?? '*'}';
