import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

enum RibbonTab { home, insert, layout, styles, review }

class MarkdownEditorPane extends StatefulWidget {
  const MarkdownEditorPane({
    super.key,
    required this.initialMarkdown,
    required this.onSave,
    this.onSaveAs,
    required this.onClose,
    this.readOnly = false,
  });

  final String initialMarkdown;
  final ValueChanged<String> onSave;
  final ValueChanged<String>? onSaveAs;
  final VoidCallback onClose;
  final bool readOnly;

  @override
  State<MarkdownEditorPane> createState() => _MarkdownEditorPaneState();
}

class _MarkdownEditorPaneState extends State<MarkdownEditorPane> {
  late final TextEditingController _textController;
  RibbonTab _activeTab = RibbonTab.home;
  bool _showPreview = true;
  double _fontSize = 14.0;
  String _selectedFontFamily = 'Arial';
  double _lineSpacing = 1.5;

  static const Color accentGreen = Color(0xFF22C55E);
  static const Color panelBg = Color(0xFF0F172A);
  static const Color ribbonBg = Color(0xFF1E293B);
  static const Color borderCol = Color(0xFF334155);

  static const List<String> _fontFamilies = <String>[
    'Arial',
    'Calibri',
    'Helvetica',
    'Times New Roman',
    'Courier New',
    'Georgia',
    'Roboto',
    'Open Sans',
    'Segoe UI',
    'Verdana',
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialMarkdown);
  }

  @override
  void didUpdateWidget(covariant MarkdownEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMarkdown != widget.initialMarkdown) {
      _textController.text = widget.initialMarkdown;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _insertFormatting(String prefix, String suffix) {
    final selection = _textController.selection;
    final text = _textController.text;
    if (!selection.isValid) {
      _textController.text = '$text$prefix$suffix';
      return;
    }
    final selectedText = selection.textInside(text);
    final replacement = '$prefix$selectedText$suffix';
    final newText = text.replaceRange(selection.start, selection.end, replacement);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length + suffix.length,
      ),
    );
  }

  void _insertBlock(String blockText) {
    final text = _textController.text;
    final selection = _textController.selection;
    if (selection.isValid) {
      final newText = text.replaceRange(selection.start, selection.end, '\n$blockText\n');
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + blockText.length + 2),
      );
    } else {
      _textController.text = '$text\n$blockText\n';
    }
  }

  void _applyStylePreset(String preset) {
    switch (preset) {
      case 'title':
        _insertFormatting('# ', '');
        break;
      case 'heading1':
        _insertFormatting('# ', '');
        break;
      case 'heading2':
        _insertFormatting('## ', '');
        break;
      case 'heading3':
        _insertFormatting('### ', '');
        break;
      case 'subtitle':
        _insertFormatting('_*', '*_');
        break;
      case 'quote':
        _insertFormatting('> ', '');
        break;
      case 'code':
        _insertFormatting('```\n', '\n```');
        break;
      case 'normal':
      default:
        break;
    }
  }

  void _changeCase(String mode) {
    final selection = _textController.selection;
    final text = _textController.text;
    final target = selection.isValid && !selection.isCollapsed
        ? selection.textInside(text)
        : text;

    if (target.isEmpty) return;

    String transformed = target;
    if (mode == 'upper') {
      transformed = target.toUpperCase();
    } else if (mode == 'lower') {
      transformed = target.toLowerCase();
    } else if (mode == 'title') {
      transformed = target
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}' : '')
          .join(' ');
    } else if (mode == 'sentence') {
      transformed = target.isNotEmpty ? '${target[0].toUpperCase()}${target.substring(1).toLowerCase()}' : target;
    }

    if (selection.isValid && !selection.isCollapsed) {
      final newText = text.replaceRange(selection.start, selection.end, transformed);
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + transformed.length),
      );
    } else {
      _textController.text = transformed;
    }
  }

  Future<void> _pickAndInsertImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _insertBlock('![Image]($path)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: panelBg,
      child: Column(
        children: <Widget>[
          // Top Header & Ribbon Tab Bar
          _buildRibbonHeader(context),
          // Active Ribbon Shelf
          _buildRibbonShelf(context),
          // Content Editor View
          Expanded(
            child: _showPreview ? _buildMarkdownPreview(context) : _buildCodeEditor(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonHeader(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: ribbonBg,
        border: Border(bottom: BorderSide(color: borderCol)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.edit_document, color: accentGreen, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Document Studio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          // Ribbon Tabs Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _tabButton('Home', RibbonTab.home, Icons.home_outlined),
                _tabButton('Insert', RibbonTab.insert, Icons.add_box_outlined),
                _tabButton('Layout', RibbonTab.layout, Icons.grid_view_outlined),
                _tabButton('Styles', RibbonTab.styles, Icons.style_outlined),
                _tabButton('Review', RibbonTab.review, Icons.analytics_outlined),
              ],
            ),
          ),
          const Spacer(),
          // Action Buttons
          Tooltip(
            message: _showPreview ? 'Switch to Raw Code Editor' : 'Switch to Rendered Preview',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: Colors.white70,
                side: const BorderSide(color: borderCol),
              ),
              onPressed: () => setState(() => _showPreview = !_showPreview),
              icon: Icon(_showPreview ? Icons.code_rounded : Icons.visibility_rounded, size: 16),
              label: Text(_showPreview ? 'Code' : 'Preview', style: const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.onSaveAs != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accentGreen,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 32),
              ),
              onPressed: () => widget.onSave(_textController.text),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: const Text('Save', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: borderCol),
                minimumSize: const Size(0, 32),
              ),
              onPressed: () => widget.onSaveAs!(_textController.text),
              icon: const Icon(Icons.drive_file_move_rounded, size: 16),
              label: const Text('Save As...', style: TextStyle(fontSize: 11)),
            ),
          ] else ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accentGreen,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 32),
              ),
              onPressed: () => widget.onSave(_textController.text),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
              label: const Text('Save As New PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: borderCol),
              minimumSize: const Size(0, 32),
            ),
            onPressed: widget.onClose,
            icon: const Icon(Icons.auto_stories_rounded, size: 16),
            label: const Text('Back to Reader', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, RibbonTab tab, IconData icon) {
    final bool isSelected = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          backgroundColor: isSelected ? accentGreen.withValues(alpha: 0.15) : Colors.transparent,
          foregroundColor: isSelected ? accentGreen : Colors.white60,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: isSelected ? const BorderSide(color: accentGreen, width: 1) : BorderSide.none,
          ),
        ),
        onPressed: () => setState(() => _activeTab = tab),
        icon: Icon(icon, size: 14),
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _buildRibbonShelf(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF131C2E),
        border: Border(bottom: BorderSide(color: borderCol)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: switch (_activeTab) {
          RibbonTab.home => _buildHomeRibbon(),
          RibbonTab.insert => _buildInsertRibbon(),
          RibbonTab.layout => _buildLayoutRibbon(),
          RibbonTab.styles => _buildStylesRibbon(),
          RibbonTab.review => _buildReviewRibbon(),
        },
      ),
    );
  }

  // --- HOME RIBBON TAB ---
  Widget _buildHomeRibbon() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Clipboard Group
          _ribbonGroup(
            title: 'Clipboard',
            children: [
              _iconBtn(
                icon: Icons.content_copy_rounded,
                tooltip: 'Copy Selected',
                onTap: () {
                  final selection = _textController.selection;
                  final text = selection.isValid && !selection.isCollapsed
                      ? selection.textInside(_textController.text)
                      : _textController.text;
                  Clipboard.setData(ClipboardData(text: text));
                },
              ),
              _iconBtn(
                icon: Icons.content_cut_rounded,
                tooltip: 'Cut Selected',
                onTap: () {
                  final selection = _textController.selection;
                  if (selection.isValid && !selection.isCollapsed) {
                    Clipboard.setData(ClipboardData(text: selection.textInside(_textController.text)));
                    _textController.text = _textController.text.replaceRange(selection.start, selection.end, '');
                  }
                },
              ),
              _iconBtn(
                icon: Icons.select_all_rounded,
                tooltip: 'Select All',
                onTap: () {
                  _textController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _textController.text.length,
                  );
                },
              ),
            ],
          ),
          _vDivider(),

          // Font & Typography Group
          _ribbonGroup(
            title: 'Font & Typography',
            children: [
              // Font Family Selector
              SizedBox(
                width: 120,
                height: 32,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedFontFamily,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    filled: true,
                    fillColor: panelBg,
                  ),
                  dropdownColor: ribbonBg,
                  items: _fontFamilies
                      .map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 11, color: Colors.white))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedFontFamily = val);
                  },
                ),
              ),
              const SizedBox(width: 4),
              // Font Size Spinner
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: panelBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderCol),
                ),
                child: Row(
                  children: [
                    _iconBtn(
                      icon: Icons.remove,
                      tooltip: 'Decrease Size',
                      onTap: () => setState(() => _fontSize = (_fontSize - 1).clamp(8, 72)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('${_fontSize.toInt()}pt', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                    _iconBtn(
                      icon: Icons.add,
                      tooltip: 'Increase Size',
                      onTap: () => setState(() => _fontSize = (_fontSize + 1).clamp(8, 72)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Typography Toggles
              _iconBtn(icon: Icons.format_bold_rounded, tooltip: 'Bold (Ctrl+B)', onTap: () => _insertFormatting('**', '**')),
              _iconBtn(icon: Icons.format_italic_rounded, tooltip: 'Italic (Ctrl+I)', onTap: () => _insertFormatting('*', '*')),
              _iconBtn(icon: Icons.format_underlined_rounded, tooltip: 'Underline', onTap: () => _insertFormatting('<u>', '</u>')),
              _iconBtn(icon: Icons.strikethrough_s_rounded, tooltip: 'Strikethrough', onTap: () => _insertFormatting('~~', '~~')),
              _iconBtn(icon: Icons.superscript_rounded, tooltip: 'Superscript', onTap: () => _insertFormatting('<sup>', '</sup>')),
              _iconBtn(icon: Icons.subscript_rounded, tooltip: 'Subscript', onTap: () => _insertFormatting('<sub>', '</sub>')),
            ],
          ),
          _vDivider(),

          // Paragraph & Alignment Group
          _ribbonGroup(
            title: 'Paragraph & Alignment',
            children: [
              _iconBtn(icon: Icons.format_align_left_rounded, tooltip: 'Align Left', onTap: () {}),
              _iconBtn(icon: Icons.format_align_center_rounded, tooltip: 'Align Center', onTap: () {}),
              _iconBtn(icon: Icons.format_align_right_rounded, tooltip: 'Align Right', onTap: () {}),
              _iconBtn(icon: Icons.format_align_justify_rounded, tooltip: 'Justify', onTap: () {}),
              const SizedBox(width: 4),
              _iconBtn(icon: Icons.format_list_bulleted_rounded, tooltip: 'Bullet List', onTap: () => _insertFormatting('- ', '')),
              _iconBtn(icon: Icons.format_list_numbered_rounded, tooltip: 'Numbered List', onTap: () => _insertFormatting('1. ', '')),
              _iconBtn(icon: Icons.checklist_rounded, tooltip: 'Task Checklist', onTap: () => _insertFormatting('- [ ] ', '')),
              _iconBtn(icon: Icons.format_quote_rounded, tooltip: 'Blockquote', onTap: () => _insertFormatting('> ', '')),
              _iconBtn(icon: Icons.format_indent_increase_rounded, tooltip: 'Indent', onTap: () => _insertFormatting('  ', '')),
            ],
          ),
          _vDivider(),

          // Quick Styles Group
          _ribbonGroup(
            title: 'Quick Presets',
            children: [
              _styleChip('Normal', 'normal'),
              _styleChip('H1 Title', 'heading1'),
              _styleChip('H2 Section', 'heading2'),
              _styleChip('H3 Sub', 'heading3'),
              _styleChip('Quote', 'quote'),
              _styleChip('Code', 'code'),
            ],
          ),
        ],
      ),
    );
  }

  // --- INSERT RIBBON TAB ---
  Widget _buildInsertRibbon() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _ribbonGroup(
            title: 'Tables & Media',
            children: [
              _actionChip('Table', Icons.table_chart_outlined, () {
                _insertBlock('| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Item 1 | Item 2 | Item 3 |');
              }),
              _actionChip('Image', Icons.image_outlined, _pickAndInsertImage),
              _actionChip('Hyperlink', Icons.link_outlined, () {
                _insertFormatting('[Link Title](', ')');
              }),
            ],
          ),
          _vDivider(),
          _ribbonGroup(
            title: 'Structure & Breaks',
            children: [
              _actionChip('Page Divider', Icons.horizontal_rule_rounded, () {
                _insertBlock('\n---\n');
              }),
              _actionChip('Callout Box', Icons.mark_chat_read_outlined, () {
                _insertBlock('> **NOTE:** Important details go here.');
              }),
              _actionChip('Code Block', Icons.code_rounded, () {
                _insertBlock('```dart\n// Enter code snippet here\n```');
              }),
              _actionChip('Math Formula', Icons.functions_rounded, () {
                _insertBlock('\$\$\nE = mc^2\n\$\$');
              }),
              _actionChip('Footnote', Icons.short_text_rounded, () {
                _insertFormatting('[^1]', '\n\n[^1]: Footnote description here.');
              }),
            ],
          ),
        ],
      ),
    );
  }

  // --- LAYOUT RIBBON TAB ---
  Widget _buildLayoutRibbon() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _ribbonGroup(
            title: 'Page Setup',
            children: [
              const Icon(Icons.description_outlined, color: Colors.white60, size: 16),
              const SizedBox(width: 6),
              const Text('Size:', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(width: 4),
              _dropdown<String>(
                value: 'A4',
                items: const ['A4', 'Letter', 'Legal'],
                onChanged: (_) {},
              ),
              const SizedBox(width: 10),
              const Icon(Icons.crop_rotate_rounded, color: Colors.white60, size: 16),
              const SizedBox(width: 6),
              const Text('Orientation:', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(width: 4),
              _dropdown<String>(
                value: 'Portrait',
                items: const ['Portrait', 'Landscape'],
                onChanged: (_) {},
              ),
            ],
          ),
          _vDivider(),
          _ribbonGroup(
            title: 'Spacing & Scale',
            children: [
              const Text('Line Height:', style: TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(width: 6),
              _dropdown<double>(
                value: _lineSpacing,
                items: const [1.0, 1.15, 1.5, 2.0],
                labelBuilder: (v) => '${v}x',
                onChanged: (v) {
                  if (v != null) setState(() => _lineSpacing = v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- STYLES RIBBON TAB ---
  Widget _buildStylesRibbon() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _styleThemeCard('Modern Academic', 'Serif Headings, Clean Spacing', () {
            _insertBlock('# Academic Thesis Title\n## Abstract\nDocument text content...');
          }),
          const SizedBox(width: 8),
          _styleThemeCard('Executive Brief', 'Bold Sans, Accent Banners', () {
            _insertBlock('# Executive Summary\n> **Key Takeaway:** High impact overview.');
          }),
          const SizedBox(width: 8),
          _styleThemeCard('Technical Doc', 'Monospace Blocks, Code Syntax', () {
            _insertBlock('# API Specification\n```json\n{ "status": "ok" }\n```');
          }),
        ],
      ),
    );
  }

  // --- REVIEW RIBBON TAB ---
  Widget _buildReviewRibbon() {
    final text = _textController.text;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final chars = text.length;
    final lines = text.isEmpty ? 0 : text.split('\n').length;
    final readingTimeMin = (words / 200).ceil();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _ribbonGroup(
            title: 'Document Statistics',
            children: [
              _statTile('$words', 'Words'),
              _statTile('$chars', 'Chars'),
              _statTile('$lines', 'Lines'),
              _statTile('${readingTimeMin}m', 'Read Time'),
            ],
          ),
          _vDivider(),
          _ribbonGroup(
            title: 'Case Converters',
            children: [
              _actionChip('UPPERCASE', Icons.text_fields_rounded, () => _changeCase('upper')),
              _actionChip('lowercase', Icons.text_format_rounded, () => _changeCase('lower')),
              _actionChip('Title Case', Icons.title_rounded, () => _changeCase('title')),
              _actionChip('Sentence case', Icons.format_size_rounded, () => _changeCase('sentence')),
            ],
          ),
        ],
      ),
    );
  }

  // --- RIBBON UI HELPERS ---
  Widget _ribbonGroup({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: children),
        const SizedBox(height: 4),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _vDivider() {
    return Container(
      height: 36,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: borderCol,
    );
  }

  Widget _iconBtn({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: borderCol.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _styleChip(String label, String preset) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: 'Apply $label style',
        child: ActionChip(
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          backgroundColor: panelBg,
          side: const BorderSide(color: borderCol),
          label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
          onPressed: () => _applyStylePreset(preset),
        ),
      ),
    );
  }

  Widget _actionChip(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        avatar: Icon(icon, size: 14, color: accentGreen),
        label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
        backgroundColor: panelBg,
        side: const BorderSide(color: borderCol),
        onPressed: onTap,
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    String Function(T)? labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      height: 28,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          filled: true,
          fillColor: panelBg,
        ),
        dropdownColor: ribbonBg,
        items: items
            .map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelBuilder != null ? labelBuilder(item) : item.toString(),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _styleThemeCard(String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderCol),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(subtitle, style: const TextStyle(fontSize: 9, color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentGreen)),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
        ],
      ),
    );
  }

  // --- EDITOR / PREVIEW BODIES ---
  Widget _buildMarkdownPreview(BuildContext context) {
    return Container(
      color: panelBg,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: MarkdownBody(
          data: _textController.text,
          imageBuilder: (uri, title, alt) {
            final src = uri.toString();
            if (src.startsWith('data:image/') && src.contains('base64,')) {
              try {
                final base64Str = src.split('base64,').last.replaceAll(RegExp(r'\s+'), '');
                final bytes = base64Decode(base64Str);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                );
              } catch (_) {}
            }
            try {
              final parsedUri = Uri.tryParse(src);
              final filePath = parsedUri != null && parsedUri.scheme == 'file'
                  ? parsedUri.toFilePath()
                  : src;
              final file = File(filePath);
              if (file.existsSync()) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.file(file, fit: BoxFit.contain),
                );
              }
            } catch (_) {}
            return Text('[Image: ${alt ?? 'Asset'}]', style: const TextStyle(color: Colors.white54));
          },
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: _fontSize,
              height: _lineSpacing,
              fontFamily: _selectedFontFamily,
            ),
            h1: TextStyle(color: Colors.white, fontSize: _fontSize + 10, fontWeight: FontWeight.bold, fontFamily: _selectedFontFamily),
            h2: TextStyle(color: Colors.white, fontSize: _fontSize + 6, fontWeight: FontWeight.bold, fontFamily: _selectedFontFamily),
            h3: TextStyle(color: Colors.white, fontSize: _fontSize + 3, fontWeight: FontWeight.w600, fontFamily: _selectedFontFamily),
            code: const TextStyle(fontFamily: 'monospace', backgroundColor: Color(0xFF1E293B), color: accentGreen),
            blockquoteDecoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(4),
              border: const Border(left: BorderSide(color: accentGreen, width: 3)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeEditor(BuildContext context) {
    return Container(
      color: const Color(0xFF090D16),
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _textController,
        maxLines: null,
        expands: true,
        readOnly: widget.readOnly,
        style: TextStyle(
          fontFamily: 'monospace',
          color: const Color(0xFFF8FAFC),
          fontSize: _fontSize,
          height: _lineSpacing,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Enter or edit document Markdown content...',
          hintStyle: TextStyle(color: Colors.white38),
        ),
      ),
    );
  }
}
