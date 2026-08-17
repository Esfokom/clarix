import 'package:flutter/material.dart';

class RecoveryBanner extends StatelessWidget {
  const RecoveryBanner({
    required this.revision,
    required this.onReview,
    required this.onDismiss,
    super.key,
  });

  final int revision;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    key: const Key('recoverable-project-banner'),
    content: Text('Recovered durable PDF edits at revision $revision.'),
    leading: const Icon(Icons.restore),
    actions: <Widget>[
      TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
      FilledButton(onPressed: onReview, child: const Text('Review edits')),
    ],
  );
}
