import 'package:flutter/material.dart';
import 'package:clarix/src/features/ai/ai.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:pdfrx/pdfrx.dart';

import '../../../core/workspace_surface_tokens.dart';

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
  InlinePageReferenceBuilder({
    required this.document,
    required this.documentRef,
    required this.onNavigate,
    required this.colors,
  });

  final AiDocumentContext? document;
  final PdfDocumentRef? documentRef;
  final ValueChanged<CitationSnippet>? onNavigate;
  final WorkspaceSurfaceTokens colors;
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
      document: document,
      documentRef: documentRef,
      onNavigate: onNavigate,
      pageNumber: pageNumber,
      label: element.textContent,
      textStyle: preferredStyle ?? parentStyle,
      colors: colors,
    );
  }
}

class _InlinePageReference extends StatefulWidget {
  const _InlinePageReference({
    super.key,
    required this.document,
    required this.documentRef,
    required this.onNavigate,
    required this.pageNumber,
    required this.label,
    required this.textStyle,
    required this.colors,
  });

  final AiDocumentContext? document;
  final PdfDocumentRef? documentRef;
  final ValueChanged<CitationSnippet>? onNavigate;
  final int pageNumber;
  final String label;
  final TextStyle? textStyle;
  final WorkspaceSurfaceTokens colors;

  @override
  State<_InlinePageReference> createState() => _InlinePageReferenceState();
}

class _InlinePageReferenceState extends State<_InlinePageReference> {
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
    final document = widget.document;
    final bool interactive =
        document != null &&
        !document.isMissingFile &&
        widget.documentRef != null;
    final TextStyle style = (widget.textStyle ?? const TextStyle()).copyWith(
      color: widget.colors.accent,
      decoration: TextDecoration.underline,
      decorationColor: widget.colors.accent,
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
          onTap: () => widget.onNavigate?.call(
            CitationSnippet(
              documentId: document.documentId,
              label: document.title,
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
          color: widget.colors.panelRaised,
          elevation: 18,
          child: SizedBox(
            width: _previewWidth,
            height: _previewHeight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: PdfDocumentViewBuilder(
                documentRef: widget.documentRef!,
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
