import 'package:flutter/material.dart';

import 'package:clarix/src/features/pdf_editor/pdf_editor.dart';

class DirtyCloseDialog extends StatelessWidget {
  const DirtyCloseDialog({
    required this.onChoice,
    required this.onCancel,
    super.key,
  });

  final ValueChanged<EditorCloseChoice> onChoice;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Unsaved PDF edits'),
    content: const Text(
      'Your editing project is durable. Choose how to close this document.',
    ),
    actions: <Widget>[
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
      TextButton(
        key: const Key('discard-to-recovery'),
        onPressed: () => onChoice(EditorCloseChoice.discardToRecovery),
        child: const Text('Discard to Recovery'),
      ),
      TextButton(
        key: const Key('keep-recoverable-project'),
        onPressed: () => onChoice(EditorCloseChoice.keepRecoverableProject),
        child: const Text('Keep Recoverable Project'),
      ),
      FilledButton(
        key: const Key('save-pdf-before-close'),
        onPressed: () => onChoice(EditorCloseChoice.savePdf),
        child: const Text('Save PDF'),
      ),
    ],
  );
}

Future<EditorCloseChoice?> showDirtyCloseDialog(BuildContext context) =>
    showDialog<EditorCloseChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => DirtyCloseDialog(
        onChoice: (choice) => Navigator.pop(dialogContext, choice),
        onCancel: () => Navigator.pop(dialogContext),
      ),
    );
