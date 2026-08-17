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

/// Phase 1 formatting surface backed by the canonical editor session.
///
/// The legacy panel above remains available until the feature-flag migration
/// in Task 17. This panel never constructs legacy PDF mutation intents.
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

  EditorTextStyle get _style {
    final offset = widget.selection.range.start;
    return widget.object.runs
            .where((run) => run.start <= offset && offset <= run.end)
            .map((run) => run.style)
            .firstOrNull ??
        widget.object.runs.first.style;
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
  }

  @override
  void didUpdateWidget(covariant CanonicalPdfTextFormatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object != widget.object ||
        oldWidget.selection != widget.selection) {
      _sizeController.text = _style.fontSize.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _sizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final families = <String>{
      ?style.fontFamily,
      ...widget.availableFamilies,
    }.toList(growable: false);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Text format', style: Theme.of(context).textTheme.titleMedium),
          if (widget.object.capability != 'editable')
            Text(
              widget.object.capabilityReason ?? 'This text is read only.',
              key: const Key('canonical-format-read-only-reason'),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('font-family-field'),
            initialValue: style.fontFamily,
            decoration: const InputDecoration(labelText: 'Font family'),
            items: families
                .map(
                  (family) => DropdownMenuItem<String>(
                    value: family,
                    child: Text(family),
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
          const SizedBox(height: 12),
          TextField(
            key: const Key('font-size-field'),
            controller: _sizeController,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Size (pt)'),
            onSubmitted: (value) {
              final size = double.tryParse(value);
              if (size != null && size > 0) {
                _submit(styleWith(style, fontSize: size));
              }
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilterChip(
                key: const Key('canonical-font-bold'),
                label: const Text('Bold'),
                selected: style.fontWeight >= 600,
                onSelected: _enabled
                    ? (_) => _submit(
                        styleWith(
                          style,
                          fontWeight: style.fontWeight >= 600 ? 400 : 700,
                        ),
                      )
                    : null,
              ),
              FilterChip(
                key: const Key('canonical-font-italic'),
                label: const Text('Italic'),
                selected: style.italic,
                onSelected: _enabled
                    ? (_) => _submit(styleWith(style, italic: !style.italic))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Paragraph alignment and automatic shrinking are unavailable in Phase 1.',
            key: Key('canonical-phase-one-format-limits'),
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
