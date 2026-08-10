import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/models.dart';
import '../../application/workspace_providers.dart';
import 'workspace_common.dart';

class InlinePageReferenceSyntax extends markdown.InlineSyntax {
  InlinePageReferenceSyntax()
    : super(
        r'\bpages?\s+(\d+)(?:(?:\s+and\s+|\s*[-–]\s*)\d+)?\b',
        caseSensitive: false,
      );

  @override
  bool onMatch(markdown.InlineParser parser, Match match) {
    final markdown.Element element = markdown.Element.text(
      'inline-page-reference',
      match.group(0)!,
    )..attributes['page'] = match.group(1)!;
    parser.addNode(element);
    return true;
  }
}

class InlinePageReferenceBuilder extends MarkdownElementBuilder {
  InlinePageReferenceBuilder({required this.activeTab});

  final DocumentTabState? activeTab;
  final Map<int, int> _occurrences = <int, int>{};

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    markdown.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final int? pageNumber = int.tryParse(element.attributes['page'] ?? '');
    if (pageNumber == null) {
      return Text(element.textContent, style: preferredStyle ?? parentStyle);
    }

    final int occurrence = (_occurrences[pageNumber] ?? 0) + 1;
    _occurrences[pageNumber] = occurrence;
    return _InlinePageReference(
      key: Key(
        occurrence == 1
            ? 'inline-page-reference-$pageNumber'
            : 'inline-page-reference-$pageNumber-$occurrence',
      ),
      tab: activeTab,
      pageNumber: pageNumber,
      label: element.textContent,
      textStyle: preferredStyle ?? parentStyle,
    );
  }
}

class _InlinePageReference extends ConsumerStatefulWidget {
  const _InlinePageReference({
    super.key,
    required this.tab,
    required this.pageNumber,
    required this.label,
    required this.textStyle,
  });

  final DocumentTabState? tab;
  final int pageNumber;
  final String label;
  final TextStyle? textStyle;

  @override
  ConsumerState<_InlinePageReference> createState() =>
      _InlinePageReferenceState();
}

class _InlinePageReferenceState extends ConsumerState<_InlinePageReference> {
  static const double _previewWidth = 184;
  static const double _previewHeight = 226;
  static const double _previewGap = 8;
  final LayerLink _previewLink = LayerLink();
  OverlayEntry? _preview;

  @override
  void dispose() {
    _removePreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DocumentTabState? tab = widget.tab;
    final bool interactive = tab != null && !tab.isMissingFile;
    final TextStyle style = (widget.textStyle ?? const TextStyle()).copyWith(
      color: WorkspaceColors.accent,
      decoration: TextDecoration.underline,
      decorationColor: WorkspaceColors.accent,
      fontWeight: FontWeight.w600,
    );
    final Widget label = Text(widget.label, style: style);

    if (!interactive) {
      return label;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _showPreview(),
      onExit: (_) => _removePreview(),
      child: CompositedTransformTarget(
        link: _previewLink,
        child: GestureDetector(
          onTap: () => ref
              .read(workspaceNotifierProvider.notifier)
              .navigateToCitation(
                CitationSnippet(
                  documentId: tab.documentId,
                  label: tab.title,
                  pageNumber: widget.pageNumber,
                  snippet: widget.label,
                ),
              ),
          child: label,
        ),
      ),
    );
  }

  void _showPreview() {
    if (_preview != null) return;
    final tab = widget.tab!;
    final RenderBox target = context.findRenderObject()! as RenderBox;
    final Rect targetRect = target.localToGlobal(Offset.zero) & target.size;
    final Size viewport = MediaQuery.sizeOf(context);
    final double left = targetRect.left
        .clamp(_previewGap, viewport.width - _previewWidth - _previewGap)
        .toDouble();
    final bool showBelow =
        viewport.height - targetRect.bottom >= _previewHeight + _previewGap ||
        targetRect.top < _previewHeight + _previewGap;
    final double top = showBelow
        ? targetRect.bottom + _previewGap
        : targetRect.top - _previewHeight - _previewGap;
    _preview = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        left: left,
        top: top
            .clamp(_previewGap, viewport.height - _previewHeight - _previewGap)
            .toDouble(),
        child: Material(
          color: WorkspaceColors.panelRaised,
          elevation: 18,
          child: SizedBox(
            width: _previewWidth,
            height: _previewHeight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: PdfDocumentViewBuilder(
                documentRef: ref.read(pdfDocumentRefProvider(tab.filePath)),
                builder: (BuildContext _, PdfDocument? document) =>
                    document == null
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PdfPageView(
                        document: document,
                        pageNumber: widget.pageNumber,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_preview!);
  }

  void _removePreview() {
    _preview?.remove();
    _preview = null;
  }
}
