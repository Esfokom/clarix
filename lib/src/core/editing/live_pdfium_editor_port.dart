import '../../features/pdf_editor/infrastructure/live_pdfium_session.dart';
import '../../features/pdf_editor/infrastructure/pdfium_edit_plan_applier.dart';
import 'editor_bridge.dart';
import 'editor_bridge_types.dart';

/// Serializes a semantic prepared command with its mutation of the sole live
/// PDFium document.  A failed application never publishes the Rust revision.
final class LivePdfiumEditorPort implements NativeLivePdfiumPort {
  LivePdfiumEditorPort({
    required this._semantic,
    required this._session,
    required this._resolveLocator,
  });

  final NativeLivePdfiumPort _semantic;
  final LivePdfiumSession _session;
  final EditorPhysicalLocator Function(String sourceKey) _resolveLocator;

  @override
  Future<EditorPreparedLiveCommand> prepareLiveCommand(
    EditorCommandRequest request,
  ) => _semantic.prepareLiveCommand(request);

  /// Applies the plan before publication. Callers use this instead of calling
  /// [prepareLiveCommand] and [publishPreparedLiveCommand] independently.
  Future<EditorCommandResult> submit(EditorCommandRequest request) async {
    final prepared = await _semantic.prepareLiveCommand(request);
    final replacements = prepared.plan.operations
        .map(
          (operation) => LivePdfiumTextReplacement(
            locator: _resolveLocator(operation.sourceKey),
            replacement: operation.replacement,
            expectedText: operation.expectedText,
          ),
        )
        .toList(growable: false);
    await _session.apply(LivePdfiumEditPlan(replacements: replacements));
    return _semantic.publishPreparedLiveCommand(prepared.token);
  }

  @override
  Future<EditorCommandResult> publishPreparedLiveCommand(String token) =>
      _semantic.publishPreparedLiveCommand(token);
}
