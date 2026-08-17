import '../../../core/editing/editor_bridge_types.dart';
import 'editor_session_controller.dart';

extension EditorSessionInspection on EditorSessionController {
  Future<EditorSearchResult> searchDocument({
    required String query,
    EditorSearchMode mode = EditorSearchMode.exact,
    bool wholeWord = false,
    int offset = 0,
    int limit = 100,
  }) {
    ensureActiveForFeature();
    return phaseTwoGatewayForFeature.search(
      EditorSearchRequest(
        expectedRevision: revisionForFeature,
        query: query,
        mode: mode,
        wholeWord: wholeWord,
        offset: offset,
        limit: limit,
      ),
    );
  }

  Future<EditorSelectionSet> validateSelection(EditorSelectionSet selection) {
    ensureActiveForFeature();
    return phaseTwoGatewayForFeature.validateSelection(selection);
  }

  Future<EditorCompatibilityReport> compatibilityReport() {
    ensureActiveForFeature();
    return phaseTwoGatewayForFeature.compatibilityReport(revisionForFeature);
  }

  Future<void> reportMemoryPressure(EditorMemoryPressureLevel level) {
    ensureActiveForFeature();
    return phaseTwoGatewayForFeature.reportMemoryPressure(level);
  }

  Future<EditorAnnotation> annotationDetails(String objectId) {
    ensureActiveForFeature();
    return phaseTwoGatewayForFeature.annotationDetails(objectId);
  }

  Future<EditorCommandResult> createAnnotation(EditorAnnotation annotation) =>
      submitPhaseTwoMutationForFeature(
        (gateway, commandId, baseRevision) => gateway.createAnnotation(
          commandId: commandId,
          baseRevision: baseRevision,
          annotation: annotation,
        ),
      );

  Future<EditorCommandResult> updateAnnotation(EditorAnnotation annotation) =>
      submitPhaseTwoMutationForFeature(
        (gateway, commandId, baseRevision) => gateway.updateAnnotation(
          commandId: commandId,
          baseRevision: baseRevision,
          annotation: annotation,
        ),
      );

  Future<EditorCommandResult> deleteAnnotation(String objectId) =>
      submitPhaseTwoMutationForFeature(
        (gateway, commandId, baseRevision) => gateway.deleteAnnotation(
          commandId: commandId,
          baseRevision: baseRevision,
          objectId: objectId,
        ),
      );
}
