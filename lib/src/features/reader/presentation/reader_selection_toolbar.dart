import 'package:flutter/material.dart';

class ReaderSelectionToolbar extends StatelessWidget {
  const ReaderSelectionToolbar({
    required this.anchorAbove,
    required this.anchorBelow,
    required this.highlightColors,
    required this.onCopy,
    required this.onAskAi,
    required this.onNote,
    required this.onBookmark,
    required this.onReadAloud,
    required this.onHighlight,
    required this.onMoreColors,
    super.key,
  });

  final Offset anchorAbove;
  final Offset anchorBelow;
  final List<int> highlightColors;
  final VoidCallback onCopy;
  final VoidCallback onAskAi;
  final VoidCallback onNote;
  final VoidCallback onBookmark;
  final VoidCallback onReadAloud;
  final ValueChanged<int> onHighlight;
  final VoidCallback onMoreColors;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: CustomSingleChildLayout(
      delegate: TextSelectionToolbarLayoutDelegate(
        anchorAbove: anchorAbove,
        anchorBelow: anchorBelow,
      ),
      child: Material(
        key: const Key('reader-selection-toolbar'),
        color: const Color(0xFF424242),
        borderRadius: BorderRadius.circular(10),
        elevation: 10,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 16,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _SelectionAction(
                  key: const Key('reader-selection-copy'),
                  icon: Icons.copy_outlined,
                  label: 'Copy',
                  onPressed: onCopy,
                ),
                _SelectionAction(
                  key: const Key('reader-selection-ask-ai'),
                  icon: Icons.auto_awesome_outlined,
                  label: 'Ask AI',
                  onPressed: onAskAi,
                ),
                _SelectionAction(
                  key: const Key('reader-selection-note'),
                  icon: Icons.edit_note_outlined,
                  label: 'Note',
                  onPressed: onNote,
                ),
                _SelectionAction(
                  key: const Key('reader-selection-bookmark'),
                  icon: Icons.bookmark_border,
                  label: 'Bookmark',
                  onPressed: onBookmark,
                ),
                _SelectionAction(
                  key: const Key('reader-selection-read-aloud'),
                  icon: Icons.volume_up_outlined,
                  label: 'Read aloud',
                  onPressed: onReadAloud,
                ),
                const _ToolbarDivider(),
                ...highlightColors.map(
                  (int color) => _HighlightColorButton(
                    key: Key('reader-highlight-${color.toRadixString(16)}'),
                    color: Color(color),
                    onPressed: () => onHighlight(color),
                  ),
                ),
                _SelectionAction(
                  key: const Key('reader-selection-more-colors'),
                  label: 'More colours',
                  onPressed: onMoreColors,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required super.key,
    this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: icon == null
        ? null
        : Icon(icon, size: 18, color: const Color(0xFFF5F5F5)),
    label: Text(
      label,
      style: const TextStyle(
        color: Color(0xFFF5F5F5),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

class _HighlightColorButton extends StatelessWidget {
  const _HighlightColorButton({
    required super.key,
    required this.color,
    required this.onPressed,
  });

  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: InkResponse(
      onTap: onPressed,
      radius: 20,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white30),
        ),
      ),
    ),
  );
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 7),
    color: Colors.white24,
  );
}
