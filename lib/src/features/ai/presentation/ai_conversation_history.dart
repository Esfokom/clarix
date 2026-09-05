part of 'ai_side_pane.dart';

/// Conversation history rendered in place of the transcript.
///
/// Rows animate in on a single controller with a per-row interval so the list
/// resolves as one staggered sweep rather than a batch of independent fades.
class _ConversationHistoryPanel extends StatefulWidget {
  const _ConversationHistoryPanel({
    required this.threads,
    required this.isLoading,
    required this.activeThreadId,
    required this.colors,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final List<ConversationThread> threads;
  final bool isLoading;
  final String? activeThreadId;
  final WorkspaceSurfaceTokens colors;
  final ValueChanged<String> onOpen;
  final ValueChanged<ConversationThread> onDelete;

  @override
  State<_ConversationHistoryPanel> createState() =>
      _ConversationHistoryPanelState();
}

class _ConversationHistoryPanelState extends State<_ConversationHistoryPanel>
    with SingleTickerProviderStateMixin {
  static const int _staggerCount = 8;

  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    if (!widget.isLoading) _entrance.forward();
  }

  @override
  void didUpdateWidget(covariant _ConversationHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading && !widget.isLoading) {
      _entrance.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WorkspaceSurfaceTokens colors = widget.colors;
    if (widget.isLoading) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
      );
    }
    if (widget.threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(LucideIcons.history, color: colors.textFaint, size: 22),
              const SizedBox(height: 12),
              Text(
                'No saved conversations yet',
                key: const Key('ai-history-empty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textStrong,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ask something about this document and the exchange is kept '
                'here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final String countLabel = widget.threads.length == 1
        ? '1 CONVERSATION'
        : '${widget.threads.length} CONVERSATIONS';

    return Column(
      key: const Key('ai-history-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            countLabel,
            style: TextStyle(
              color: colors.textFaint,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            itemCount: widget.threads.length,
            itemBuilder: (BuildContext context, int index) {
              final ConversationThread thread = widget.threads[index];
              final double start =
                  index.clamp(0, _staggerCount) / (_staggerCount * 2);
              final Animation<double> animation = CurvedAnimation(
                parent: _entrance,
                curve: Interval(start, 1, curve: Curves.easeOutCubic),
              );
              return AnimatedBuilder(
                animation: animation,
                builder: (BuildContext context, Widget? child) => Opacity(
                  opacity: animation.value.clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - animation.value)),
                    child: child,
                  ),
                ),
                child: _ConversationHistoryTile(
                  thread: thread,
                  isActive: thread.id == widget.activeThreadId,
                  colors: colors,
                  onOpen: () => widget.onOpen(thread.id),
                  onDelete: () => widget.onDelete(thread),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConversationHistoryTile extends StatefulWidget {
  const _ConversationHistoryTile({
    required this.thread,
    required this.isActive,
    required this.colors,
    required this.onOpen,
    required this.onDelete,
  });

  final ConversationThread thread;
  final bool isActive;
  final WorkspaceSurfaceTokens colors;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_ConversationHistoryTile> createState() =>
      _ConversationHistoryTileState();
}

class _ConversationHistoryTileState extends State<_ConversationHistoryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final WorkspaceSurfaceTokens colors = widget.colors;
    final String? summary = widget.thread.summary?.trim();
    // The conversation that was open before history was raised keeps an accent
    // card, so returning to it is a matter of recognition rather than reading.
    final Color background = widget.isActive
        ? colors.accentSoft
        : (_hovered
              ? Color.alphaBlend(
                  colors.accent.withValues(alpha: 0.07),
                  colors.panelRaised,
                )
              : colors.panelRaised);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: Key('conversation-thread-${widget.thread.id}'),
          onTap: widget.onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(13, 11, 7, 11),
            decoration: ShapeDecoration(
              color: background,
              shape: SmoothRectangleBorder(
                smoothness: 0.8,
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: widget.isActive
                      ? colors.accentBorder
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textStrong,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: <Widget>[
                          Icon(
                            widget.isActive
                                ? LucideIcons.messageSquareDot
                                : LucideIcons.messageSquare,
                            size: 11,
                            color: widget.isActive
                                ? colors.accent
                                : colors.textFaint,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              summary == null || summary.isEmpty
                                  ? formatConversationTimestamp(
                                      widget.thread.updatedAt,
                                    )
                                  : summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textFaint,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: _hovered ? 1 : 0,
                  child: IconButton(
                    key: Key('delete-conversation-${widget.thread.id}'),
                    tooltip: 'Delete conversation',
                    visualDensity: VisualDensity.compact,
                    iconSize: 14,
                    color: colors.textFaint,
                    onPressed: _hovered ? widget.onDelete : null,
                    icon: const Icon(LucideIcons.trash2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned counterpart to the composer: while history is open this is the only
/// thing the pane offers to write with, so it sits where the composer would be.
class _PinnedNewConversationBar extends StatelessWidget {
  const _PinnedNewConversationBar({
    required this.colors,
    required this.onPressed,
  });

  final WorkspaceSurfaceTokens colors;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: SizedBox(
        height: 42,
        width: double.infinity,
        child: ShadButton(
          key: const Key('ai-new-conversation'),
          backgroundColor: colors.accentSoft,
          hoverBackgroundColor: Color.alphaBlend(
            colors.accent.withValues(alpha: 0.12),
            colors.accentSoft,
          ),
          foregroundColor: colors.textStrong,
          decoration: ShadDecoration(
            border: ShadBorder.all(
              color: colors.accentBorder,
              radius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          leading: Icon(LucideIcons.squarePen, size: 15, color: colors.accent),
          child: const Text(
            'New conversation',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// Compact, chronology-friendly stamp for a conversation row.
String formatConversationTimestamp(DateTime timestamp, {DateTime? now}) {
  final DateTime local = timestamp.toLocal();
  final DateTime reference = (now ?? DateTime.now()).toLocal();
  final Duration elapsed = reference.difference(local);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  if (elapsed.inDays == 1) return 'Yesterday';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final String stamp = '${local.day} ${months[local.month - 1]}';
  return local.year == reference.year ? stamp : '$stamp ${local.year}';
}
