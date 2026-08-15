import 'package:flutter/material.dart';

class FontFallbackProposal {
  const FontFallbackProposal({
    required this.token,
    required this.fontName,
    required this.source,
    required this.embeddingAllowed,
    required this.affectedCharacters,
  });

  final String token;
  final String fontName;
  final String source;
  final bool embeddingAllowed;
  final String affectedCharacters;
}

class FontFallbackDialog extends StatelessWidget {
  const FontFallbackDialog({
    required this.proposal,
    required this.onApprove,
    required this.onReject,
    super.key,
  });

  final FontFallbackProposal proposal;
  final ValueChanged<String> onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Approve font fallback'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Proposed font: ${proposal.fontName}'),
        Text('Source: ${proposal.source}'),
        Text(
          proposal.embeddingAllowed
              ? 'Embedding is permitted.'
              : 'Embedding is not permitted.',
        ),
        Text('Affected characters: ${proposal.affectedCharacters}'),
        const SizedBox(height: 8),
        const Text('No text will change unless you approve this fallback.'),
      ],
    ),
    actions: <Widget>[
      TextButton(
        key: const Key('reject-font-fallback'),
        onPressed: onReject,
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('approve-font-fallback'),
        onPressed: proposal.embeddingAllowed
            ? () => onApprove(proposal.token)
            : null,
        child: const Text('Approve'),
      ),
    ],
  );
}
