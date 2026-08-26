import 'package:flutter/material.dart';

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
                selected: italic ?? false,
                onPressed: () =>
                    _apply(PdfTextStylePatch(italic: !(italic ?? false))),
              ),
              _Toggle(
                key: const Key('pdf-font-underline'),
                label: 'U',
                selected: underline ?? false,
                onPressed: () =>
                    _apply(PdfTextStylePatch(underline: !(underline ?? false))),
              ),
              _Toggle(
                key: const Key('pdf-font-superscript'),
                label: 'x²',
                selected: (shift ?? 0) > 0,
                onPressed: () => _apply(
                  PdfTextStylePatch(baselineShift: (shift ?? 0) > 0 ? 0 : 0.35),
                ),
              ),
              _Toggle(
                key: const Key('pdf-font-subscript'),
                label: 'x₂',
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
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
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

final class _CanonicalPdfTextFormatPanelState
    extends State<CanonicalPdfTextFormatPanel> {
  late final TextEditingController _sizeController;
  late final TextEditingController _lineHeightController;
  late final TextEditingController _charSpacingController;
  late final TextEditingController _scaleController;

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
    }
  }

  @override
  void dispose() {
    _sizeController.dispose();
    _lineHeightController.dispose();
    _charSpacingController.dispose();
    _scaleController.dispose();
    super.dispose();
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
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Format',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              const Icon(Icons.tune, size: 16),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(Icons.arrow_drop_down, size: 18),
              const SizedBox(width: 4),
              Text(
                'Text Style',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.object.capability != 'editable')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.object.capabilityReason ?? 'This text is read only.',
                key: const Key('canonical-format-read-only-reason'),
                style: TextStyle(color: colorScheme.error, fontSize: 11),
              ),
            ),
          // Row 1: Font family & Font size & Color
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
              const SizedBox(width: 6),
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
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              const SizedBox(width: 6),
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
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: B, I, U, S, T^1, T_1
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
                selected: false,
                textStyle: const TextStyle(decoration: TextDecoration.underline),
                enabled: _enabled,
                onPressed: () {},
              ),
              _StyleIconButton(
                key: const Key('canonical-font-strikethrough'),
                label: 'S',
                tooltip: 'Strikethrough',
                selected: false,
                textStyle: const TextStyle(decoration: TextDecoration.lineThrough),
                enabled: _enabled,
                onPressed: () {},
              ),
              _StyleIconButton(
                key: const Key('canonical-font-superscript'),
                label: 'T¹',
                tooltip: 'Superscript',
                selected: false,
                enabled: _enabled,
                onPressed: () {},
              ),
              _StyleIconButton(
                key: const Key('canonical-font-subscript'),
                label: 'T₁',
                tooltip: 'Subscript',
                selected: false,
                enabled: _enabled,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 3: Alignment (Left, Center, Right, Justify)
          Row(
            children: <Widget>[
              _AlignmentButton(
                icon: Icons.format_align_left,
                tooltip: 'Align Left',
                selected: true,
                enabled: _enabled,
                onPressed: () {},
              ),
              const SizedBox(width: 4),
              _AlignmentButton(
                icon: Icons.format_align_center,
                tooltip: 'Center',
                selected: false,
                enabled: _enabled,
                onPressed: () {},
              ),
              const SizedBox(width: 4),
              _AlignmentButton(
                icon: Icons.format_align_right,
                tooltip: 'Align Right',
                selected: false,
                enabled: _enabled,
                onPressed: () {},
              ),
              const SizedBox(width: 4),
              _AlignmentButton(
                icon: Icons.format_align_justify,
                tooltip: 'Justify',
                selected: false,
                enabled: _enabled,
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 4: Metrics (Line Height, Char Spacing, Scale)
          Row(
            children: <Widget>[
              Expanded(
                child: _MetricInputField(
                  icon: Icons.format_line_spacing,
                  tooltip: 'Line Spacing',
                  controller: _lineHeightController,
                  enabled: _enabled,
                  onSubmitted: (value) {},
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricInputField(
                  icon: Icons.space_bar,
                  tooltip: 'Character Spacing',
                  controller: _charSpacingController,
                  enabled: _enabled,
                  onSubmitted: (value) {},
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MetricInputField(
                  icon: Icons.aspect_ratio,
                  tooltip: 'Horizontal Scale (%)',
                  controller: _scaleController,
                  enabled: _enabled,
                  onSubmitted: (value) {},
                ),
              ),
            ],
          ),
        ],
      ),
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
}) => EditorTextStyle(
  fontFamily: fontFamily ?? source.fontFamily,
  fontSize: fontSize ?? source.fontSize,
  fontWeight: fontWeight ?? source.fontWeight,
  italic: italic ?? source.italic,
  colorRgba: colorRgba ?? source.colorRgba,
);
