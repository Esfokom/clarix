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

    return _InlinePageReference(
      key: Key('inline-page-reference-$pageNumber'),
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
  bool _hovered = false;

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
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          GestureDetector(
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
          if (_hovered)
            Positioned(
              left: 0,
              bottom: 24,
              width: 220,
              height: 270,
              child: Material(
                color: WorkspaceColors.panelRaised,
                elevation: 12,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: PdfDocumentViewBuilder(
                    documentRef: ref.watch(
                      pdfDocumentRefProvider(tab.filePath),
                    ),
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
        ],
      ),
    );
  }
}
