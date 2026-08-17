class EditorTextRange {
  const EditorTextRange({required this.start, required this.end})
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;
}

class EditorSelection {
  const EditorSelection({
    required this.objectId,
    required this.range,
    this.affinity = EditorSelectionAffinity.downstream,
  });

  final String objectId;
  final EditorTextRange range;
  final EditorSelectionAffinity affinity;
}

enum EditorSelectionAffinity { upstream, downstream }
