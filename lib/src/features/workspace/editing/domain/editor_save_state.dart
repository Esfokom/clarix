enum EditorSavePhase { clean, dirty, saving, failed }

class EditorSaveState {
  const EditorSaveState({
    this.phase = EditorSavePhase.clean,
    this.stage,
    this.errorCode,
  });

  final EditorSavePhase phase;
  final String? stage;
  final String? errorCode;

  EditorSaveState copyWith({
    EditorSavePhase? phase,
    String? stage,
    String? errorCode,
    bool clearStage = false,
    bool clearError = false,
  }) => EditorSaveState(
    phase: phase ?? this.phase,
    stage: clearStage ? null : (stage ?? this.stage),
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
  );
}
