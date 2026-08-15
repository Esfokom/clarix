import 'package:flutter/material.dart';

class SaveConflictDialog extends StatelessWidget {
  const SaveConflictDialog({
    required this.errorCode,
    required this.onSaveAs,
    required this.onCancel,
    this.onRetry,
    this.onRebase,
    super.key,
  });

  final String errorCode;
  final VoidCallback onSaveAs;
  final VoidCallback onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRebase;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_title),
    content: Text(_message),
    actions: <Widget>[
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
      if (errorCode == 'source_changed' && onRebase != null)
        TextButton(onPressed: onRebase, child: const Text('Rebase')),
      if (_locked && onRetry != null)
        TextButton(
          key: const Key('retry-native-save'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      if (errorCode != 'validation_failed')
        FilledButton(
          key: const Key('native-save-as'),
          onPressed: onSaveAs,
          child: const Text('Save As'),
        ),
    ],
  );

  bool get _locked =>
      errorCode == 'sharing_violation' || errorCode == 'target_locked';

  String get _title => switch (errorCode) {
    'source_changed' => 'The source PDF changed',
    'sharing_violation' || 'target_locked' => 'The PDF is in use',
    'validation_failed' => 'The saved copy failed validation',
    _ => 'Could not save the PDF',
  };

  String get _message => switch (errorCode) {
    'source_changed' =>
      'Save As to preserve both versions, or rebase after reviewing the external changes.',
    'sharing_violation' || 'target_locked' =>
      'Close the PDF in other applications, retry, or choose a new destination.',
    'validation_failed' =>
      'The original PDF was preserved. The invalid temporary copy was not installed.',
    _ => 'Your recoverable editing project is unchanged.',
  };
}

class SaveAsAssociationDialog extends StatelessWidget {
  const SaveAsAssociationDialog({
    required this.onKeepOriginal,
    required this.onFollowNewSource,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onKeepOriginal;
  final VoidCallback onFollowNewSource;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('After Save As'),
    content: const Text(
      'Choose which PDF this editing project should follow after the copy is saved.',
    ),
    actions: <Widget>[
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
      TextButton(
        key: const Key('keep-original-association'),
        onPressed: onKeepOriginal,
        child: const Text('Keep editing original'),
      ),
      FilledButton(
        key: const Key('follow-new-source'),
        onPressed: onFollowNewSource,
        child: const Text('Follow saved copy'),
      ),
    ],
  );
}

Future<bool?> showSaveAsAssociationDialog(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => SaveAsAssociationDialog(
        onKeepOriginal: () => Navigator.pop(dialogContext, false),
        onFollowNewSource: () => Navigator.pop(dialogContext, true),
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
