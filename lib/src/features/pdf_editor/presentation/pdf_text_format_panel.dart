import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import '../domain/editor_selection.dart';
import '../domain/pdf_edit_intent.dart';
import '../domain/pdf_text_types.dart';

final class PdfTextFormatPanel extends StatefulWidget {
  const PdfTextFormatPanel({
    required this.documentId,
    required this.documentRevision,
    required this.block,
    required this.selection,
    required this.availableFamilies,
    required this.onIntent,
    this.caseMatching = true,
    this.onCaseMatchingChanged,
    this.substitutionMessage,
    super.key,
  });

  final String documentId;
  final String documentRevision;
  final PdfTextBlock block;
  final PdfTextSelection selection;
  final List<String> availableFamilies;
  final ValueChanged<PdfEditIntent> onIntent;
  final bool caseMatching;
  final ValueChanged<bool>? onCaseMatchingChanged;
  final String? substitutionMessage;

  @override
  State<PdfTextFormatPanel> createState() => _PdfTextFormatPanelState();
}

final class _PdfTextFormatPanelState extends State<PdfTextFormatPanel> {
  late final TextEditingController _sizeController;

  PdfTextRange get _range => widget.selection.range.isEmpty
      ? PdfTextRange(0, widget.block.text.length)
      : widget.selection.range;

  List<PdfTextStyle> get _selectedStyles => widget.block.runs
      .where(
        (run) => run.range.end > _range.start && run.range.start < _range.end,
      )
      .map((run) => run.style)
      .toList(growable: false);

  T? _common<T>(T Function(PdfTextStyle style) read) {
    final values = _selectedStyles.map(read).toSet();
    return values.length == 1 ? values.single : null;
  }

  @override
  void initState() {
    super.initState();
    final size = _common((style) => style.fontSize);
    _sizeController = TextEditingController(text: size?.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant PdfTextFormatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block ||
        oldWidget.selection != widget.selection) {
      final size = _common((style) => style.fontSize);
      _sizeController.text = size?.toStringAsFixed(1) ?? '';
    }
  }

  @override
  void dispose() {
    _sizeController.dispose();
    super.dispose();
  }

  void _apply(PdfTextStylePatch patch) => widget.onIntent(
    FormatPdfTextIntent(
      documentId: widget.documentId,
      documentRevision: widget.documentRevision,
      locator: widget.block.locator,
      range: _range,
      patch: patch,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final family = _common((style) => style.fontFamily);
    final size = _common((style) => style.fontSize);
    final weight = _common((style) => style.fontWeight);
    final italic = _common((style) => style.italic);
    final underline = _common((style) => style.underline);
    final fillColor = _common((style) => style.fillColorValue);
    final shift = _common((style) => style.baselineShift);
    final alignment = _common((style) => style.alignment);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Text format', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          DropdownMenu<String>(
            key: const Key('pdf-font-search'),
            width: double.infinity,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            initialSelection: widget.availableFamilies.contains(family)
                ? family
                : null,
            label: const Text('Font family'),
            dropdownMenuEntries: widget.availableFamilies
                .map(
                  (value) =>
                      DropdownMenuEntry<String>(value: value, label: value),
                )
                .toList(growable: false),
            onSelected: (value) {
              if (value != null) _apply(PdfTextStylePatch(fontFamily: value));
            },
          ),
          const SizedBox(height: 12),
          if (size == null)
            const Text(
              'Mixed sizes',
              key: Key('pdf-font-size-mixed'),
              style: TextStyle(fontSize: 12),
            ),
          TextField(
            key: const Key('pdf-font-size-input'),
            controller: _sizeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Size (pt)'),
            onSubmitted: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null && parsed > 0) {
                _apply(PdfTextStylePatch(fontSize: parsed));
              }
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: <Widget>[
              PopupMenuButton<int>(
                key: const Key('pdf-font-color'),
                tooltip: 'Font color',
                initialValue: fillColor,
                onSelected: (value) =>
                    _apply(PdfTextStylePatch(fillColorValue: value)),
                itemBuilder: (context) => const <PopupMenuEntry<int>>[
                  PopupMenuItem(value: 0xff000000, child: Text('Black')),
                  PopupMenuItem(value: 0xff374151, child: Text('Slate')),
                  PopupMenuItem(value: 0xffdc2626, child: Text('Red')),
                  PopupMenuItem(value: 0xff2563eb, child: Text('Blue')),
                  PopupMenuItem(value: 0xff16a34a, child: Text('Green')),
                ],
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'A',
                    style: TextStyle(
                      color: Color(fillColor ?? 0xff000000),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              _Toggle(
                key: const Key('pdf-font-bold'),
                label: 'B',
                tooltip: 'Bold',
                selected: weight != null && weight >= 600,
                onPressed: () => _apply(
                  PdfTextStylePatch(
                    fontWeight: weight != null && weight >= 600 ? 400 : 700,
                  ),
                ),
              ),
              _Toggle(
                key: const Key('pdf-font-italic'),
                label: 'I',
                tooltip: 'Italic',
                selected: italic ?? false,
                onPressed: () =>
                    _apply(PdfTextStylePatch(italic: !(italic ?? false))),
              ),
              _Toggle(
                key: const Key('pdf-font-underline'),
                label: 'U',
                tooltip: 'Underline',
                selected: underline ?? false,
                onPressed: () =>
                    _apply(PdfTextStylePatch(underline: !(underline ?? false))),
              ),
              _Toggle(
                key: const Key('pdf-font-superscript'),
                label: 'x²',
                tooltip: 'Superscript',
                selected: (shift ?? 0) > 0,
                onPressed: () => _apply(
                  PdfTextStylePatch(baselineShift: (shift ?? 0) > 0 ? 0 : 0.35),
                ),
              ),
              _Toggle(
                key: const Key('pdf-font-subscript'),
                label: 'x₂',
                tooltip: 'Subscript',
                selected: (shift ?? 0) < 0,
                onPressed: () => _apply(
                  PdfTextStylePatch(baselineShift: (shift ?? 0) < 0 ? 0 : -0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            key: const Key('pdf-text-alignment'),
            children: <Widget>[
              _AlignmentToggle(
                key: const Key('pdf-align-left'),
                icon: Icons.format_align_left,
                label: 'Align left',
                selected: alignment == PdfTextAlignment.left,
                onPressed: () => _apply(
                  const PdfTextStylePatch(alignment: PdfTextAlignment.left),
                ),
              ),
              _AlignmentToggle(
                key: const Key('pdf-align-center'),
                icon: Icons.format_align_center,
                label: 'Align center',
                selected: alignment == PdfTextAlignment.center,
                onPressed: () => _apply(
                  const PdfTextStylePatch(alignment: PdfTextAlignment.center),
                ),
              ),
              _AlignmentToggle(
                key: const Key('pdf-align-right'),
                icon: Icons.format_align_right,
                label: 'Align right',
                selected: alignment == PdfTextAlignment.right,
                onPressed: () => _apply(
                  const PdfTextStylePatch(alignment: PdfTextAlignment.right),
                ),
              ),
              _AlignmentToggle(
                key: const Key('pdf-align-justify'),
                icon: Icons.format_align_justify,
                label: 'Justify',
                selected: alignment == PdfTextAlignment.justify,
                onPressed: () => _apply(
                  const PdfTextStylePatch(alignment: PdfTextAlignment.justify),
                ),
              ),
            ],
          ),
          ExpansionTile(
            key: const Key('pdf-text-geometry'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Geometry'),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _geometryInput(
                      key: const Key('pdf-geometry-x'),
                      label: 'X',
                      value: widget.block.bounds.left,
                      onValue: (value) {
                        final dx = value - widget.block.bounds.left;
                        _move(
                          PdfBox(
                            value,
                            widget.block.bounds.bottom,
                            widget.block.bounds.right + dx,
                            widget.block.bounds.top,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _geometryInput(
                      key: const Key('pdf-geometry-y'),
                      label: 'Y',
                      value: widget.block.bounds.bottom,
                      onValue: (value) {
                        final dy = value - widget.block.bounds.bottom;
                        _move(
                          PdfBox(
                            widget.block.bounds.left,
                            value,
                            widget.block.bounds.right,
                            widget.block.bounds.top + dy,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _geometryInput(
                      key: const Key('pdf-geometry-width'),
                      label: 'Width',
                      value: widget.block.bounds.width,
                      onValue: (value) => _resize(
                        PdfBox(
                          widget.block.bounds.left,
                          widget.block.bounds.bottom,
                          widget.block.bounds.left +
                              value.clamp(4, double.infinity),
                          widget.block.bounds.top,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _geometryInput(
                      key: const Key('pdf-geometry-height'),
                      label: 'Height',
                      value: widget.block.bounds.height,
                      onValue: (value) => _resize(
                        PdfBox(
                          widget.block.bounds.left,
                          widget.block.bounds.bottom,
                          widget.block.bounds.right,
                          widget.block.bounds.bottom +
                              value.clamp(4, double.infinity),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SwitchListTile(
            key: const Key('pdf-case-matching'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Match replacement casing'),
            value: widget.caseMatching,
            onChanged: widget.onCaseMatchingChanged,
          ),
          if (widget.substitutionMessage case final message?)
            Container(
              key: const Key('pdf-font-substitution-warning'),
              padding: const EdgeInsets.all(10),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Text(message),
            ),
        ],
      ),
    );
  }

  Widget _geometryInput({
    required Key key,
    required String label,
    required double value,
    required ValueChanged<double> onValue,
  }) => TextFormField(
    key: key,
    initialValue: value.toStringAsFixed(1),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    onFieldSubmitted: (text) {
      final parsed = double.tryParse(text);
      if (parsed != null) onValue(parsed);
    },
  );

  void _move(PdfBox bounds) => widget.onIntent(
    MovePdfTextBlockIntent(
      documentId: widget.documentId,
      documentRevision: widget.documentRevision,
      locator: widget.block.locator,
      bounds: bounds,
    ),
  );

  void _resize(PdfBox bounds) => widget.onIntent(
    ResizePdfTextBlockIntent(
      documentId: widget.documentId,
      documentRevision: widget.documentRevision,
      locator: widget.block.locator,
      bounds: bounds,
    ),
  );
}

final class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    super.key,
  });
  final String label;
  final String? tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}

final class _AlignmentToggle extends StatelessWidget {
  const _AlignmentToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: IconButton(
          isSelected: selected,
          selectedIcon: Icon(icon),
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    ),
  );
}

/// Formatting surface backed by the canonical editor session.
final class CanonicalPdfTextFormatPanel extends StatefulWidget {
  const CanonicalPdfTextFormatPanel({
    required this.session,
    required this.object,
    required this.selection,
    this.availableFamilies = const <String>[],
    super.key,
  });

  final EditorSessionController session;
  final EditorSceneObject object;
  final EditorSelection selection;
  final List<String> availableFamilies;

  @override
  State<CanonicalPdfTextFormatPanel> createState() =>
      _CanonicalPdfTextFormatPanelState();
}

enum EditorRibbonTab { home, insert, layout, references, review, view }

final class _CanonicalPdfTextFormatPanelState
    extends State<CanonicalPdfTextFormatPanel> {
  late final TextEditingController _sizeController;
  late final TextEditingController _lineHeightController;
  late final TextEditingController _charSpacingController;
  late final TextEditingController _scaleController;
  late final TextEditingController _textEditingController;
  late final TextEditingController _docTitleController;
  late final TextEditingController _docAuthorController;

  EditorRibbonTab _activeRibbonTab = EditorRibbonTab.home;

  static const List<String> _commonFontFamilies = <String>[
    'Helvetica',
    'Arial',
    'Times New Roman',
    'Times',
    'Courier',
    'Courier New',
    'Roboto',
    'Open Sans',
    'Georgia',
    'Verdana',
    'Segoe UI',
    'Calibri',
  ];

  EditorTextStyle get _style {
    final offset = widget.selection.range.start;
    return widget.object.runs
            .where((run) => run.start <= offset && offset <= run.end)
            .map((run) => run.style)
            .firstOrNull ??
        widget.object.runs.firstOrNull?.style ??
        const EditorTextStyle(
          fontSize: 12,
          fontWeight: 400,
          italic: false,
          colorRgba: <int>[0, 0, 0, 255],
        );
  }

  bool get _enabled =>
      widget.object.capability == 'editable' &&
      !widget.session.commandOutstanding;

  @override
  void initState() {
    super.initState();
    _sizeController = TextEditingController(
      text: _style.fontSize.toStringAsFixed(1),
    );
    _lineHeightController = TextEditingController(
      text: (widget.object.layout?.lineHeight ?? 14.0).toStringAsFixed(2),
    );
    _charSpacingController = TextEditingController(
      text: (widget.object.layout?.characterSpacing ?? 0.0).toStringAsFixed(2),
    );
    _scaleController = TextEditingController(
      text: ((widget.object.layout?.horizontalScale ?? 1.0) * 100).toStringAsFixed(0),
    );
    _textEditingController = TextEditingController(
      text: widget.object.text ?? '',
    );
    _docTitleController = TextEditingController(text: 'Clarix PDF Document');
    _docAuthorController = TextEditingController(text: 'Author');
  }

  @override
  void didUpdateWidget(covariant CanonicalPdfTextFormatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object != widget.object ||
        oldWidget.selection != widget.selection) {
      _sizeController.text = _style.fontSize.toStringAsFixed(1);
      _lineHeightController.text =
          (widget.object.layout?.lineHeight ?? 14.0).toStringAsFixed(2);
      _charSpacingController.text =
          (widget.object.layout?.characterSpacing ?? 0.0).toStringAsFixed(2);
      _scaleController.text =
          ((widget.object.layout?.horizontalScale ?? 1.0) * 100).toStringAsFixed(0);
      if (_textEditingController.text != (widget.object.text ?? '')) {
        _textEditingController.text = widget.object.text ?? '';
      }
    }
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _lineHeightController.dispose();
    _charSpacingController.dispose();
    _scaleController.dispose();
    _textEditingController.dispose();
    _docTitleController.dispose();
    _docAuthorController.dispose();
    super.dispose();
  }

  void _applyTextReplacement(String newText) {
    final currentText = widget.object.text ?? '';
    widget.session.dispatchCommand(
      EditorCommand(
        kind: EditorCommandKind.replaceTextRange,
        objectId: widget.object.objectId,
        start: 0,
        end: currentText.length,
        replacement: newText,
      ),
    );
  }

  void _insertSnippet(String snippet) {
    final currentText = _textEditingController.text;
    final updated = '$currentText\n$snippet';
    _textEditingController.text = updated;
    _applyTextReplacement(updated);
  }

  void _applyParagraphStylePreset(String preset) {
    switch (preset) {
      case 'heading1':
        _submit(styleWith(_style, fontSize: 24, fontWeight: 700, italic: false));
        break;
      case 'heading2':
        _submit(styleWith(_style, fontSize: 18, fontWeight: 700, italic: false));
        break;
      case 'heading3':
        _submit(styleWith(_style, fontSize: 14, fontWeight: 700, italic: false));
        break;
      case 'title':
        _submit(styleWith(_style, fontSize: 28, fontWeight: 800, italic: false));
        break;
      case 'subtitle':
        _submit(styleWith(_style, fontSize: 15, fontWeight: 400, italic: true));
        break;
      case 'code':
        _submit(styleWith(_style, fontFamily: 'Courier', fontSize: 11, fontWeight: 400, italic: false));
        break;
      case 'normal':
      default:
        _submit(styleWith(_style, fontSize: 12, fontWeight: 400, italic: false));
        break;
    }
  }

  void _toggleBulletList() {
    final text = widget.object.text ?? '';
    final lines = text.split('\n');
    final isBulleted = lines.every((line) => line.startsWith('• '));
    final newLines = lines.map((line) {
      if (isBulleted) {
        return line.startsWith('• ') ? line.substring(2) : line;
      } else {
        return '• $line';
      }
    }).join('\n');
    _textEditingController.text = newLines;
    _applyTextReplacement(newLines);
  }

  void _toggleNumberedList() {
    final text = widget.object.text ?? '';
    final lines = text.split('\n');
    final isNumbered = lines.isNotEmpty && RegExp(r'^\d+\.\s').hasMatch(lines.first);
    var index = 1;
    final newLines = lines.map((line) {
      if (isNumbered) {
        return line.replaceFirst(RegExp(r'^\d+\.\s'), '');
      } else {
        return '${index++}. $line';
      }
    }).join('\n');
    _textEditingController.text = newLines;
    _applyTextReplacement(newLines);
  }

  void _indentText() {
    final text = widget.object.text ?? '';
    final lines = text.split('\n').map((line) => '  $line').join('\n');
    _textEditingController.text = lines;
    _applyTextReplacement(lines);
  }

  void _outdentText() {
    final text = widget.object.text ?? '';
    final lines = text.split('\n').map((line) {
      if (line.startsWith('  ')) return line.substring(2);
      if (line.startsWith(' ')) return line.substring(1);
      return line;
    }).join('\n');
    _textEditingController.text = lines;
    _applyTextReplacement(lines);
  }

  void _changeCase(String mode) {
    final text = widget.object.text ?? '';
    if (text.isEmpty) return;
    String result = text;
    if (mode == 'upper') {
      result = text.toUpperCase();
    } else if (mode == 'lower') {
      result = text.toLowerCase();
    } else if (mode == 'title') {
      result = text.split(' ').map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '').join(' ');
    } else if (mode == 'sentence') {
      result = text.isNotEmpty ? '${text[0].toUpperCase()}${text.substring(1).toLowerCase()}' : text;
    }
    _textEditingController.text = result;
    _applyTextReplacement(result);
  }

  Future<void> _pickAndInsertImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _insertSnippet('![Inserted Image]($path)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rgba = style.colorRgba;
    final currentColor = Color.fromARGB(rgba[3], rgba[0], rgba[1], rgba[2]);

    final allFamilies = <String>{
      if (style.fontFamily != null) style.fontFamily!,
      ...widget.availableFamilies,
      ..._commonFontFamilies,
    }.toList(growable: false);

    return Material(
      color: colorScheme.surface,
      child: Column(
        children: [
          // Ribbon Tab Bar Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ribbonTabChip('Home', EditorRibbonTab.home, Icons.home_outlined),
                  _ribbonTabChip('Insert', EditorRibbonTab.insert, Icons.add_circle_outline),
                  _ribbonTabChip('Layout', EditorRibbonTab.layout, Icons.auto_awesome_mosaic_outlined),
                  _ribbonTabChip('References', EditorRibbonTab.references, Icons.bookmark_border_outlined),
                  _ribbonTabChip('Review', EditorRibbonTab.review, Icons.rate_review_outlined),
                  _ribbonTabChip('View', EditorRibbonTab.view, Icons.visibility_outlined),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              children: [
                if (widget.object.capability != 'editable')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      widget.object.capabilityReason ?? 'This text is read only.',
                      key: const Key('canonical-format-read-only-reason'),
                      style: TextStyle(color: colorScheme.error, fontSize: 11),
                    ),
                  ),
                switch (_activeRibbonTab) {
                  EditorRibbonTab.home => _buildHomeRibbon(style, currentColor, allFamilies),
                  EditorRibbonTab.insert => _buildInsertRibbon(),
                  EditorRibbonTab.layout => _buildLayoutRibbon(),
                  EditorRibbonTab.references => _buildReferencesRibbon(),
                  EditorRibbonTab.review => _buildReviewRibbon(),
                  EditorRibbonTab.view => _buildViewRibbon(),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ribbonTabChip(String label, EditorRibbonTab tab, IconData icon) {
    final isSelected = _activeRibbonTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Switch to $label tab',
        child: ChoiceChip(
          showCheckmark: false,
          avatar: Icon(icon, size: 12, color: isSelected ? Colors.white : Colors.grey.shade700),
          label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          selected: isSelected,
          selectedColor: Theme.of(context).colorScheme.primary,
          onSelected: (_) => setState(() => _activeRibbonTab = tab),
        ),
      ),
    );
  }

  Widget _buildHomeRibbon(EditorTextStyle style, Color currentColor, List<String> allFamilies) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Undo / Redo & Clipboard Toolbar
        Row(
          children: [
            Tooltip(
              message: 'Undo (Ctrl+Z)',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => widget.session.undo(),
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Undo', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Redo (Ctrl+Shift+Z)',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => widget.session.redo(),
                icon: const Icon(Icons.redo, size: 14),
                label: const Text('Redo', style: TextStyle(fontSize: 11)),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 14),
              tooltip: 'Copy Text',
              onPressed: () => Clipboard.setData(ClipboardData(text: _textEditingController.text)),
            ),
            IconButton(
              icon: const Icon(Icons.content_cut, size: 14),
              tooltip: 'Cut Text',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _textEditingController.text));
                _textEditingController.clear();
                _applyTextReplacement('');
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Live Text Content Editor Box
        const Text('Content Editor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TextField(
          controller: _textEditingController,
          enabled: _enabled,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Edit text content...',
            contentPadding: EdgeInsets.all(8),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
            onPressed: _enabled ? () => _applyTextReplacement(_textEditingController.text) : null,
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Update Text', style: TextStyle(fontSize: 11)),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 10),

        // Style Preset Dropdown
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Style Preset',
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          initialValue: 'normal',
          items: const [
            DropdownMenuItem(value: 'normal', child: Text('Normal Text (12pt)', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'heading1', child: Text('Heading 1 (24pt Bold)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'heading2', child: Text('Heading 2 (18pt Bold)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'heading3', child: Text('Heading 3 (14pt Bold)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'title', child: Text('Title (28pt Heavy)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
            DropdownMenuItem(value: 'subtitle', child: Text('Subtitle (15pt Italic)', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic))),
            DropdownMenuItem(value: 'code', child: Text('Code Block (11pt Mono)', style: TextStyle(fontSize: 12, fontFamily: 'Courier'))),
          ],
          onChanged: _enabled ? (value) { if (value != null) _applyParagraphStylePreset(value); } : null,
        ),
        const SizedBox(height: 8),

        // Font family, Size & Step Buttons (A+, A-)
        Row(
          children: <Widget>[
            Expanded(
              flex: 5,
              child: DropdownButtonFormField<String>(
                key: const Key('font-family-field'),
                initialValue: allFamilies.contains(style.fontFamily)
                    ? style.fontFamily
                    : allFamilies.firstOrNull,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                items: allFamilies
                    .map(
                      (family) => DropdownMenuItem<String>(
                        value: family,
                        child: Text(
                          family,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _enabled
                    ? (family) {
                        if (family != null) {
                          _submit(styleWith(style, fontFamily: family));
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 3,
              child: TextField(
                key: const Key('font-size-field'),
                controller: _sizeController,
                enabled: _enabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (value) {
                  final size = double.tryParse(value);
                  if (size != null && size > 0) {
                    _submit(styleWith(style, fontSize: size));
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            _StyleIconButton(
              label: 'A+',
              tooltip: 'Increase Size',
              selected: false,
              enabled: _enabled,
              onPressed: () {
                final newSize = style.fontSize + 1.0;
                _sizeController.text = newSize.toStringAsFixed(1);
                _submit(styleWith(style, fontSize: newSize));
              },
            ),
            const SizedBox(width: 2),
            _StyleIconButton(
              label: 'A-',
              tooltip: 'Decrease Size',
              selected: false,
              enabled: _enabled,
              onPressed: () {
                final newSize = (style.fontSize - 1.0).clamp(6.0, 120.0);
                _sizeController.text = newSize.toStringAsFixed(1);
                _submit(styleWith(style, fontSize: newSize));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Typography Toggles & Colors
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            _StyleIconButton(
              key: const Key('canonical-font-bold'),
              label: 'B',
              tooltip: 'Bold',
              selected: style.fontWeight >= 600,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              enabled: _enabled,
              onPressed: () => _submit(
                styleWith(
                  style,
                  fontWeight: style.fontWeight >= 600 ? 400 : 700,
                ),
              ),
            ),
            _StyleIconButton(
              key: const Key('canonical-font-italic'),
              label: 'I',
              tooltip: 'Italic',
              selected: style.italic,
              textStyle: const TextStyle(fontStyle: FontStyle.italic),
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, italic: !style.italic)),
            ),
            _StyleIconButton(
              key: const Key('canonical-font-underline'),
              label: 'U',
              tooltip: 'Underline',
              selected: style.underline,
              textStyle: const TextStyle(decoration: TextDecoration.underline),
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, underline: !style.underline)),
            ),
            _StyleIconButton(
              key: const Key('canonical-font-strikethrough'),
              label: 'S',
              tooltip: 'Strikethrough',
              selected: style.strikethrough,
              textStyle: const TextStyle(decoration: TextDecoration.lineThrough),
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, strikethrough: !style.strikethrough)),
            ),
            _StyleIconButton(
              key: const Key('canonical-font-superscript'),
              label: 'T¹',
              tooltip: 'Superscript',
              selected: style.baselineShift > 0,
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, baselineShift: style.baselineShift > 0 ? 0.0 : 0.35)),
            ),
            _StyleIconButton(
              key: const Key('canonical-font-subscript'),
              label: 'T₁',
              tooltip: 'Subscript',
              selected: style.baselineShift < 0,
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, baselineShift: style.baselineShift < 0 ? 0.0 : -0.2)),
            ),
            _ColorPickerButton(
              color: currentColor,
              enabled: _enabled,
              onColorChanged: (newColor) {
                _submit(
                  styleWith(
                    style,
                    colorRgba: <int>[
                      (newColor.r * 255.0).round().clamp(0, 255),
                      (newColor.g * 255.0).round().clamp(0, 255),
                      (newColor.b * 255.0).round().clamp(0, 255),
                      (newColor.a * 255.0).round().clamp(0, 255),
                    ],
                  ),
                );
              },
            ),
            _HighlightColorPickerButton(
              enabled: _enabled,
              onColorChanged: (newColor) {
                _submit(
                  styleWith(
                    style,
                    highlightRgba: newColor == null ? null : <int>[
                      (newColor.r * 255.0).round().clamp(0, 255),
                      (newColor.g * 255.0).round().clamp(0, 255),
                      (newColor.b * 255.0).round().clamp(0, 255),
                      (newColor.a * 255.0).round().clamp(0, 255),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Alignment, Lists & Indentation
        Row(
          children: <Widget>[
            _AlignmentButton(
              icon: Icons.format_align_left,
              tooltip: 'Align Left',
              selected: style.alignment == 'left',
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, alignment: 'left')),
            ),
            const SizedBox(width: 4),
            _AlignmentButton(
              icon: Icons.format_align_center,
              tooltip: 'Center',
              selected: style.alignment == 'center',
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, alignment: 'center')),
            ),
            const SizedBox(width: 4),
            _AlignmentButton(
              icon: Icons.format_align_right,
              tooltip: 'Align Right',
              selected: style.alignment == 'right',
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, alignment: 'right')),
            ),
            const SizedBox(width: 4),
            _AlignmentButton(
              icon: Icons.format_align_justify,
              tooltip: 'Justify',
              selected: style.alignment == 'justify',
              enabled: _enabled,
              onPressed: () => _submit(styleWith(style, alignment: 'justify')),
            ),
            const SizedBox(width: 4),
            _StyleIconButton(
              label: '•',
              tooltip: 'Bullet List',
              selected: false,
              enabled: _enabled,
              onPressed: _toggleBulletList,
            ),
            const SizedBox(width: 2),
            _StyleIconButton(
              label: '1.',
              tooltip: 'Numbered List',
              selected: false,
              enabled: _enabled,
              onPressed: _toggleNumberedList,
            ),
            const SizedBox(width: 2),
            _StyleIconButton(
              label: '→|',
              tooltip: 'Indent',
              selected: false,
              enabled: _enabled,
              onPressed: _indentText,
            ),
            const SizedBox(width: 2),
            _StyleIconButton(
              label: '|←',
              tooltip: 'Outdent',
              selected: false,
              enabled: _enabled,
              onPressed: _outdentText,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInsertRibbon() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Insert Document Elements', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.table_chart_outlined, size: 14),
              label: const Text('Insert Table', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('| Column 1 | Column 2 |\n| --- | --- |\n| Item 1 | Item 2 |') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.image_outlined, size: 14),
              label: const Text('Insert Image', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? _pickAndInsertImage : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.horizontal_rule_outlined, size: 14),
              label: const Text('Page Break', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('\n---\n') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.format_quote_outlined, size: 14),
              label: const Text('Blockquote / Callout', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('> Important Callout: ') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.link_outlined, size: 14),
              label: const Text('Hyperlink', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('[Link Title](https://example.com)') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.code_outlined, size: 14),
              label: const Text('Code Block', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('```dart\n// Code snippet\n```') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.functions_outlined, size: 14),
              label: const Text('Math Formula', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('\$\$\nE = mc^2\n\$\$') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.space_bar_outlined, size: 14),
              label: const Text('Horizontal Rule', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('\n***\n') : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLayoutRibbon() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Page Setup & Margins', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Page Orientation',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            isDense: true,
          ),
          initialValue: 'portrait',
          items: const [
            DropdownMenuItem(value: 'portrait', child: Text('Portrait (Vertical A4)', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'landscape', child: Text('Landscape (Horizontal A4)', style: TextStyle(fontSize: 12))),
          ],
          onChanged: (_) {},
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Paper Size',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            isDense: true,
          ),
          initialValue: 'a4',
          items: const [
            DropdownMenuItem(value: 'a4', child: Text('A4 (210 x 297 mm)', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'letter', child: Text('US Letter (8.5 x 11 in)', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'legal', child: Text('US Legal (8.5 x 14 in)', style: TextStyle(fontSize: 12))),
          ],
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        const Text('Line Spacing Presets', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () => _lineHeightController.text = '12.0',
                child: const Text('1.0x', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () => _lineHeightController.text = '14.0',
                child: const Text('1.15x', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () => _lineHeightController.text = '18.0',
                child: const Text('1.5x', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () => _lineHeightController.text = '24.0',
                child: const Text('2.0x', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricInputField(
                icon: Icons.format_line_spacing,
                tooltip: 'Line Spacing (pt)',
                controller: _lineHeightController,
                enabled: _enabled,
                onSubmitted: (_) {},
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricInputField(
                icon: Icons.space_bar,
                tooltip: 'Character Spacing',
                controller: _charSpacingController,
                enabled: _enabled,
                onSubmitted: (_) {},
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _MetricInputField(
                icon: Icons.aspect_ratio,
                tooltip: 'Horizontal Scale (%)',
                controller: _scaleController,
                enabled: _enabled,
                onSubmitted: (_) {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReferencesRibbon() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Document References & Metadata', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.toc_outlined, size: 14),
              label: const Text('Insert Table of Contents', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('\n[[TOC]]\n') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.short_text_outlined, size: 14),
              label: const Text('Insert Footnote', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('[^1]\n\n[^1]: Footnote details...') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.bookmark_outline, size: 14),
              label: const Text('Insert Citation', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('(Clarix Research, 2026)') : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Document Metadata', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _docTitleController,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(labelText: 'Document Title', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _docAuthorController,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(labelText: 'Author Name', border: OutlineInputBorder(), isDense: true),
        ),
      ],
    );
  }

  Widget _buildReviewRibbon() {
    final text = _textEditingController.text;
    final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final charCount = text.length;
    final lineCount = text.isEmpty ? 0 : text.split('\n').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Review & Proofreading Toolkit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        // Live Document Statistics Card
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statWidget('$wordCount', 'Words'),
                _statWidget('$charCount', 'Chars'),
                _statWidget('$lineCount', 'Lines'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Case Conversion', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: 'UPPERCASE',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                  onPressed: _enabled ? () => _changeCase('upper') : null,
                  child: const Text('AA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Tooltip(
                message: 'lowercase',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                  onPressed: _enabled ? () => _changeCase('lower') : null,
                  child: const Text('aa', style: TextStyle(fontSize: 10)),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Tooltip(
                message: 'Title Case',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                  onPressed: _enabled ? () => _changeCase('title') : null,
                  child: const Text('Aa', style: TextStyle(fontSize: 10)),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Tooltip(
                message: 'Sentence case',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                  onPressed: _enabled ? () => _changeCase('sentence') : null,
                  child: const Text('A.a', style: TextStyle(fontSize: 10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('AI Rewrite & Polish', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('<!-- AI Polish Requested -->') : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.comment_outlined, size: 14),
              label: const Text('Add Review Note', style: TextStyle(fontSize: 11)),
              onPressed: _enabled ? () => _insertSnippet('<!-- Review Note: Check accuracy -->') : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statWidget(String count, String label) {
    return Column(
      children: [
        Text(count, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildViewRibbon() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('View & Workspace Modes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Zoom Presets', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () {},
                child: const Text('75%', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () {},
                child: const Text('100%', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () {},
                child: const Text('125%', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: EdgeInsets.zero),
                onPressed: () {},
                child: const Text('150%', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _submit(EditorTextStyle style) {
    widget.session.dispatchCommand(
      EditorCommand(
        kind: EditorCommandKind.setTextStyle,
        objectId: widget.object.objectId,
        start: widget.selection.range.start,
        end: widget.selection.range.end,
        style: style,
      ),
    );
  }
}

class _HighlightColorPickerButton extends StatelessWidget {
  const _HighlightColorPickerButton({
    required this.enabled,
    required this.onColorChanged,
  });

  final bool enabled;
  final ValueChanged<Color?> onColorChanged;

  static const List<Color> _palette = <Color>[
    Color(0xFFFEF08A), // Yellow
    Color(0xFFBBF7D0), // Green
    Color(0xFFBFDBFE), // Blue
    Color(0xFFFBCFE8), // Pink
    Color(0xFFFED7AA), // Orange
    Color(0xFFE9D5FF), // Purple
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Color?>(
      enabled: enabled,
      tooltip: 'Highlight Color',
      color: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      itemBuilder: (context) => <PopupMenuEntry<Color?>>[
        PopupMenuItem<Color?>(
          enabled: false,
          child: SizedBox(
            width: 140,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ..._palette.map((palColor) {
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      onColorChanged(palColor);
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: palColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                  );
                }),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    onColorChanged(null);
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: const Icon(Icons.block, size: 14, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFEF08A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade500),
        ),
        child: const Icon(Icons.border_color, size: 14, color: Colors.black87),
      ),
    );
  }
}

class _ColorPickerButton extends StatelessWidget {
  const _ColorPickerButton({
    required this.color,
    required this.enabled,
    required this.onColorChanged,
  });

  final Color color;
  final bool enabled;
  final ValueChanged<Color> onColorChanged;

  static const List<Color> _palette = <Color>[
    Colors.black,
    Color(0xFF262626),
    Color(0xFF525252),
    Color(0xFF737373),
    Color(0xFF2563EB),
    Color(0xFF1D4ED8),
    Color(0xFFDC2626),
    Color(0xFFB91C1C),
    Color(0xFF16A34A),
    Color(0xFF15803D),
    Color(0xFFEA580C),
    Color(0xFF9333EA),
    Color(0xFFD97706),
    Colors.white,
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Color>(
      enabled: enabled,
      tooltip: 'Font Color',
      color: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      itemBuilder: (context) => <PopupMenuEntry<Color>>[
        PopupMenuItem<Color>(
          enabled: false,
          child: SizedBox(
            width: 160,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _palette.map((palColor) {
                return InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    onColorChanged(palColor);
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: palColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
        ),
      ],
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade500),
        ),
      ),
    );
  }
}

class _StyleIconButton extends StatelessWidget {
  const _StyleIconButton({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    this.textStyle,
    super.key,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(30, 30),
          padding: EdgeInsets.zero,
          backgroundColor: selected ? theme.colorScheme.primaryContainer : null,
          side: BorderSide(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Text(label, style: textStyle?.copyWith(fontSize: 12) ?? const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _AlignmentButton extends StatelessWidget {
  const _AlignmentButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(28, 28),
            padding: EdgeInsets.zero,
            backgroundColor: selected ? theme.colorScheme.primaryContainer : null,
            side: BorderSide(
              color: selected ? theme.colorScheme.primary : theme.dividerColor,
            ),
          ),
          onPressed: enabled ? onPressed : null,
          child: Icon(icon, size: 14),
        ),
      ),
    );
  }
}

class _MetricInputField extends StatelessWidget {
  const _MetricInputField({
    required this.icon,
    required this.tooltip,
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final IconData icon;
  final String tooltip;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 13),
          prefixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

EditorTextStyle styleWith(
  EditorTextStyle source, {
  String? fontFamily,
  double? fontSize,
  int? fontWeight,
  bool? italic,
  List<int>? colorRgba,
  bool? underline,
  bool? strikethrough,
  double? baselineShift,
  String? alignment,
  List<int>? highlightRgba,
}) => EditorTextStyle(
  fontFamily: fontFamily ?? source.fontFamily,
  fontSize: fontSize ?? source.fontSize,
  fontWeight: fontWeight ?? source.fontWeight,
  italic: italic ?? source.italic,
  colorRgba: colorRgba ?? source.colorRgba,
  underline: underline ?? source.underline,
  strikethrough: strikethrough ?? source.strikethrough,
  baselineShift: baselineShift ?? source.baselineShift,
  alignment: alignment ?? source.alignment,
  highlightRgba: highlightRgba ?? source.highlightRgba,
);

