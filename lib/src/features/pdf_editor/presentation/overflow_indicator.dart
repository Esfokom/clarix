import 'package:flutter/material.dart';

class OverflowIndicator extends StatelessWidget {
  const OverflowIndicator({
    required this.message,
    required this.canIncreaseBounds,
    required this.onCancel,
    this.onIncreaseBounds,
    super.key,
  });

  final String message;
  final bool canIncreaseBounds;
  final VoidCallback onCancel;
  final VoidCallback? onIncreaseBounds;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('editor-overflow-indicator'),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (canIncreaseBounds && onIncreaseBounds != null)
            TextButton(
              key: const Key('increase-overflow-bounds'),
              onPressed: onIncreaseBounds,
              child: const Text('Increase bounds'),
            ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    ),
  );
}
