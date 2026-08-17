import '../domain/editor_save_state.dart';
import '../domain/editor_selection.dart';
import 'editor_session_controller.dart';

extension EditorSessionPresentationState on EditorSessionController {
  void updateSelection(EditorSelection? selection) {
    ensureActiveForFeature();
    replaceStateForFeature(
      stateForFeature.copyWith(
        selection: selection,
        clearSelection: selection == null,
      ),
    );
  }

  void clearError() {
    ensureActiveForFeature();
    replaceStateForFeature(stateForFeature.copyWith(clearError: true));
  }

  void dismissSaveFailure() {
    ensureActiveForFeature();
    if (stateForFeature.save.phase != EditorSavePhase.failed) return;
    replaceStateForFeature(
      stateForFeature.copyWith(
        save: stateForFeature.save.copyWith(
          phase: EditorSavePhase.dirty,
          clearError: true,
          clearStage: true,
        ),
        clearError: true,
      ),
    );
  }

  void dismissRecovery() {
    ensureActiveForFeature();
    replaceStateForFeature(stateForFeature.copyWith(clearRecovery: true));
  }
}
