const Set<String> oversizedProductionDartAllowlist = <String>{
  'lib/src/core/editing/frb_native_editor_port.dart',
  'lib/src/features/pdf_editor/application/editor_session_controller.dart',
  'lib/src/features/pdf_editor/presentation/pdf_text_format_panel.dart',
  'lib/src/features/workspace/application/workspace_notifier.dart',
};

const Set<String> temporaryFeatureBoundaryAllowlist = <String>{
  'lib/src/features/ai/application/ai_notifier.dart',
  'lib/src/features/ai/presentation/study_mode_side_pane.dart',
  'lib/src/features/reader/presentation/reader_viewer_pane.dart',
  'lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart',
  'lib/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart',
  'lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart',
  'lib/src/features/workspace/application/workspace_notifier.dart',
  'lib/src/features/workspace/application/workspace_providers.dart',
  'lib/src/features/workspace/presentation/widgets/document_workspace.dart',
  'lib/src/features/workspace/presentation/widgets/pdf_combine_extract_dialogs.dart',
  'lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart',
  'lib/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart',
};

const Set<String> temporarilyMissingFeatureEntryPoints = <String>{
  'lib/src/features/reader/reader.dart',
  'lib/src/features/tts/tts.dart',
  'lib/src/features/utilities/utilities.dart',
  'lib/src/features/workspace/workspace.dart',
};
