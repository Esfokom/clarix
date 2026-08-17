const Set<String> oversizedProductionDartAllowlist = <String>{
  'lib/src/core/editing/editor_bridge.dart',
  'lib/src/core/models.dart',
  'lib/src/features/workspace/application/workspace_notifier.dart',
  'lib/src/features/pdf_editor/application/editor_session_controller.dart',
  'lib/src/features/pdf_editor/infrastructure/pdfium_text_engine_native.dart',
  'lib/src/features/workspace/presentation/widgets/app_settings_dialog.dart',
  'lib/src/features/workspace/presentation/widgets/document_workspace.dart',
  'lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart',
};

const Set<String> temporaryFeatureBoundaryAllowlist = <String>{
  'lib/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart',
  'lib/src/features/reader_diagnostics/presentation/reader_diagnostics_hub.dart',
  'lib/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart',
  'lib/src/features/workspace/application/workspace_notifier.dart',
  'lib/src/features/workspace/application/workspace_providers.dart',
  'lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart',
};

const Set<String> temporarilyMissingFeatureEntryPoints = <String>{
  'lib/src/features/ai/ai.dart',
  'lib/src/features/reader/reader.dart',
  'lib/src/features/settings/settings.dart',
  'lib/src/features/utilities/utilities.dart',
  'lib/src/features/workspace/workspace.dart',
};
