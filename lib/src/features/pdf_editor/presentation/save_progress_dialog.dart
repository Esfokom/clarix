import 'package:flutter/material.dart';

class SaveProgressDialog extends StatelessWidget {
  const SaveProgressDialog({required this.stage, this.onCancel, super.key});

  final String stage;
  final VoidCallback? onCancel;

  bool get _atomicReplacementStarted => const <String>{
    'ReplaceOrMove',
    'Rebase',
    'RecordMaterializedRevision',
  }.contains(stage);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Saving PDF'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(_stageLabel(stage), key: const Key('save-progress-stage')),
      ],
    ),
    actions: <Widget>[
      TextButton(
        key: const Key('cancel-save'),
        onPressed: _atomicReplacementStarted ? null : onCancel,
        child: const Text('Cancel'),
      ),
    ],
  );
}

String _stageLabel(String stage) => switch (stage) {
  'CommitComposition' => 'Finishing text input…',
  'FlushCommands' => 'Flushing edits…',
  'MaterializeTemp' => 'Writing a validated copy…',
  'ValidateTemp' => 'Validating the PDF…',
  'ReplaceOrMove' => 'Replacing the destination atomically…',
  'Rebase' => 'Rebasing the editing project…',
  'RecordMaterializedRevision' => 'Recording the saved revision…',
  _ => stage,
};
