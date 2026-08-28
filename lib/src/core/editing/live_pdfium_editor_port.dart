import 'package:flutter/foundation.dart';

import '../../features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart';
import 'editor_bridge.dart';
import 'editor_bridge_types.dart';

/// An import-time, canonical association between one semantic object and one
/// PDFium object path. Its producer must observe both identities directly;
/// matching text, geometry, or traversal order after import is prohibited.
final class LivePdfiumImportBinding {
  const LivePdfiumImportBinding({
    required this.objectId,
    required this.sourceKey,
    required this.sourceRevision,
    required this.locator,
  });

  final String objectId;
  final String sourceKey;
  final String sourceRevision;
  final EditorPhysicalLocator locator;
}

final class LivePdfiumImportManifest {
  const LivePdfiumImportManifest({
    required this.sourceFingerprint,
    required this.bindings,
  });

  const LivePdfiumImportManifest.empty()
    : sourceFingerprint = null,
      bindings = const <LivePdfiumImportBinding>[];

  final String? sourceFingerprint;
  final List<LivePdfiumImportBinding> bindings;
}

final class LivePdfiumLocatorRegistry {
  final Map<String, ({EditorPhysicalLocator locator, String sourceRevision})>
  _entries =
      <String, ({EditorPhysicalLocator locator, String sourceRevision})>{};
  final Map<String, String> _sourceKeysByObjectId = <String, String>{};

  void register({
    String? objectId,
    required String sourceKey,
    required String sourceRevision,
    required EditorPhysicalLocator locator,
  }) {
    _entries[sourceKey] = (locator: locator, sourceRevision: sourceRevision);
    if (objectId != null) _sourceKeysByObjectId[objectId] = sourceKey;
  }

  void registerManifest(
    LivePdfiumImportManifest manifest, {
    required String sourceFingerprint,
  }) {
    if (manifest.sourceFingerprint != null &&
        manifest.sourceFingerprint != sourceFingerprint) {
      throw StateError('live_pdfium_manifest_source_mismatch');
    }
    for (final binding in manifest.bindings) {
      if (binding.sourceRevision != sourceFingerprint ||
          binding.locator.sourceFingerprint != sourceFingerprint) {
        throw StateError('live_pdfium_manifest_binding_mismatch');
      }
      register(
        objectId: binding.objectId,
        sourceKey: binding.sourceKey,
        sourceRevision: binding.sourceRevision,
        locator: binding.locator,
      );
    }
  }

  bool hasObject(String objectId) =>
      _sourceKeysByObjectId.containsKey(objectId);

  void clear() {
    _entries.clear();
    _sourceKeysByObjectId.clear();
  }

  EditorPhysicalLocator resolveForObject({
    required String objectId,
    required String sourceRevision,
  }) {
    final sourceKey = _sourceKeysByObjectId[objectId];
    if (sourceKey == null) throw StateError('live_pdfium_locator_not_found');
    return resolve(sourceKey: sourceKey, sourceRevision: sourceRevision);
  }

  EditorPhysicalLocator resolve({
    required String sourceKey,
    required String sourceRevision,
  }) {
    final entry = _entries[sourceKey];
    if (entry == null) throw StateError('live_pdfium_locator_not_found');
    if (entry.sourceRevision != sourceRevision) {
      throw StateError('live_pdfium_locator_stale');
    }
    return entry.locator;
  }
}

/// Serializes a semantic prepared command with its mutation of the sole live
/// PDFium document.  A failed application never publishes the Rust revision.
final class LivePdfiumEditorPort implements NativeLivePdfiumPort {
  LivePdfiumEditorPort({
    required this._semantic,
    required this._session,
    required this._locatorRegistry,
    this.onApplied,
  });

  final NativeLivePdfiumPort _semantic;
  final LivePdfiumPlanApplier _session;
  final LivePdfiumLocatorRegistry _locatorRegistry;
  final void Function(LivePdfiumApplyResult result)? onApplied;

  @override
  Future<EditorPreparedLiveCommand> prepareLiveCommand(
    EditorCommandRequest request,
  ) => _semantic.prepareLiveCommand(request);

  /// Applies the plan before publication. Callers use this instead of calling
  /// [prepareLiveCommand] and [publishPreparedLiveCommand] independently.
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    final prepared = await _semantic.prepareLiveCommand(request);
    debugPrint(
      '[editor] live plan prepared: ${prepared.plan.operations.length} '
      'operation(s), previousRevision=${prepared.plan.previousRevision} '
      'revision=${prepared.plan.revision}',
    );
    for (final operation in prepared.plan.operations) {
      debugPrint(
        '[editor]   live operation kind=${operation.kind} '
        'sourceKey=${operation.sourceKey}',
      );
    }
    final replacements = prepared.plan.operations
        .where(
          (operation) =>
              operation.kind == EditorPhysicalEditOperationKind.replaceText,
        )
        .map(
          (operation) => LivePdfiumTextReplacement(
            locator: _locatorRegistry.resolve(
              sourceKey: operation.sourceKey,
              sourceRevision: operation.sourceRevision,
            ),
            replacement: operation.replacement!,
            expectedText: operation.expectedText,
          ),
        )
        .toList(growable: false);
    final transforms = prepared.plan.operations
        .where(
          (operation) =>
              operation.kind ==
              EditorPhysicalEditOperationKind.setTextTransform,
        )
        .map(
          (operation) => LivePdfiumTextTransform(
            locator: _locatorRegistry.resolve(
              sourceKey: operation.sourceKey,
              sourceRevision: operation.sourceRevision,
            ),
            expectedTransform: operation.expectedTransform!,
            transform: operation.transform!,
            oldBounds: operation.oldBounds,
            newBounds: operation.newBounds,
          ),
        )
        .toList(growable: false);
    final applied = await _session.apply(
      LivePdfiumEditPlan(
        replacements: replacements,
        transforms: transforms,
        expectedRevision: prepared.plan.previousRevision,
        revision: prepared.plan.revision,
      ),
    );
    debugPrint(
      '[editor] live apply succeeded: revision=${applied.revision} '
      'invalidations=${applied.invalidations.length}',
    );
    final result = await _semantic.publishPreparedLiveCommand(prepared.token);
    onApplied?.call(applied);
    return result;
  }

  @override
  Future<EditorCommandResult> publishPreparedLiveCommand(String token) =>
      _semantic.publishPreparedLiveCommand(token);
}
