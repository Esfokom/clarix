import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../utilities/application/pdf_utility_service.dart';
import '../../../utilities/domain/pdf_page_selection.dart';
import '../../../utilities/domain/utility_job.dart';
import '../../../utilities/infrastructure/document_conversion_service.dart';
import '../../../utilities/infrastructure/pdf_export_service.dart';
import '../../application/workspace_providers.dart';
import 'workspace_common.dart';

typedef PickPdfSources = Future<List<String>> Function();
typedef PickPdfSource = Future<String?> Function();
typedef PickPdfDestination = Future<String?> Function();
typedef LoadPdfPageCount = Future<int> Function(String sourcePath);
typedef UtilityCompleted = FutureOr<void> Function(UtilityResult result);
typedef PickConversionSources = Future<List<String>> Function();
typedef PickConversionOutputDirectory = Future<String?> Function();
typedef ConversionCompleted =
    FutureOr<void> Function(List<UtilityResult> results);
typedef PickExportDestination =
    Future<String?> Function(UtilityFormat format, String sourcePath);

Future<void> showCombinePdfDialog(BuildContext context) => showShadDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const CombinePdfDialog(),
);

Future<void> showExtractPagesDialog(BuildContext context) =>
    showShadDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Material(
        type: MaterialType.transparency,
        child: ExtractPagesDialog(),
      ),
    );

Future<void> showConvertToPdfDialog(BuildContext context) =>
    showShadDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Material(
        type: MaterialType.transparency,
        child: ConvertToPdfDialog(),
      ),
    );

Future<void> showExportPdfDialog(BuildContext context) => showShadDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      const Material(type: MaterialType.transparency, child: ExportPdfDialog()),
);

class ExportPdfDialog extends ConsumerStatefulWidget {
  const ExportPdfDialog({
    this.service,
    this.pickSource,
    this.pickDestination,
    this.onCompleted,
    super.key,
  });

  final PdfExportService? service;
  final PickPdfSource? pickSource;
  final PickExportDestination? pickDestination;
  final UtilityCompleted? onCompleted;

  @override
  ConsumerState<ExportPdfDialog> createState() => _ExportPdfDialogState();
}

class _ExportPdfDialogState extends ConsumerState<ExportPdfDialog> {
  String? _source;
  UtilityFormat _format = UtilityFormat.markdown;
  bool _busy = false;
  String? _error;

  PdfExportService get _service => widget.service ?? PdfExportService();

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 570),
      title: const Text('Export PDF'),
      description: const Text(
        'Export a local PDF as Markdown or an image-first Office document.',
      ),
      actions: <Widget>[
        ShadButton.outline(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _source != null && !_busy ? _export : null,
          child: Text(_busy ? 'Exporting…' : 'Export'),
        ),
      ],
      child: SizedBox(
        width: 620,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ShadButton.outline(
                  leading: const Icon(LucideIcons.fileSearch, size: 15),
                  onPressed: _busy ? null : _selectSource,
                  child: Text(_source == null ? 'Select PDF' : 'Change PDF'),
                ),
                const SizedBox(width: 12),
                if (_source != null)
                  Expanded(
                    child: Text(
                      path.basename(_source!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WorkspaceColors.textStrong,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Output format',
              style: TextStyle(
                color: WorkspaceColors.textStrong,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ExportFormatOption(
                    key: const Key('export-format-markdown'),
                    label: 'Markdown',
                    detail: 'Page-by-page extracted text',
                    selected: _format == UtilityFormat.markdown,
                    onTap: _busy
                        ? null
                        : () => _selectFormat(UtilityFormat.markdown),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ExportFormatOption(
                    key: const Key('export-format-word'),
                    label: 'Word (visual)',
                    detail: 'Page image with text below',
                    selected: _format == UtilityFormat.word,
                    onTap: _busy
                        ? null
                        : () => _selectFormat(UtilityFormat.word),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ExportFormatOption(
                    key: const Key('export-format-powerpoint'),
                    label: 'PowerPoint (visual)',
                    detail: 'One page image per slide',
                    selected: _format == UtilityFormat.powerpoint,
                    onTap: _busy
                        ? null
                        : () => _selectFormat(UtilityFormat.powerpoint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WorkspaceColors.panelRaised,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WorkspaceColors.accentBorder),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    LucideIcons.info,
                    size: 15,
                    color: WorkspaceColors.textMuted,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Word and PowerPoint are visual exports. They preserve each PDF page as an image and add extracted text for search and accessibility, but do not recreate editable page layouts.',
                      style: TextStyle(
                        color: WorkspaceColors.textMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: WorkspaceColors.warning,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectFormat(UtilityFormat format) {
    setState(() {
      _format = format;
      _error = null;
    });
  }

  Future<void> _selectSource() async {
    final String? source = await (widget.pickSource ?? _pickExportPdf)();
    if (!mounted || source == null) {
      return;
    }
    setState(() {
      _source = source;
      _error = null;
    });
  }

  Future<void> _export() async {
    final String? source = _source;
    if (source == null) {
      return;
    }
    final String? destination =
        await (widget.pickDestination ?? _pickExportDestination)(
          _format,
          source,
        );
    if (!mounted || destination == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final UtilityResult result = await _service.export(
        sourcePath: source,
        format: _format,
        outputPath: destination,
      );
      final UtilityCompleted? callback = widget.onCompleted;
      if (callback != null) {
        await callback(result);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _ExportFormatOption extends StatelessWidget {
  const _ExportFormatOption({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          height: 76,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? WorkspaceColors.accentSoft
                : WorkspaceColors.panel,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? WorkspaceColors.accent : WorkspaceColors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  color: WorkspaceColors.textStrong,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WorkspaceColors.textMuted,
                  fontSize: 10,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConvertToPdfDialog extends ConsumerStatefulWidget {
  const ConvertToPdfDialog({
    this.service,
    this.pickSources,
    this.pickOutputDirectory,
    this.onCompleted,
    super.key,
  });

  final DocumentConversionService? service;
  final PickConversionSources? pickSources;
  final PickConversionOutputDirectory? pickOutputDirectory;
  final ConversionCompleted? onCompleted;

  @override
  ConsumerState<ConvertToPdfDialog> createState() => _ConvertToPdfDialogState();
}

class _ConvertToPdfDialogState extends ConsumerState<ConvertToPdfDialog> {
  final List<String> _files = <String>[];
  bool _busy = false;
  String? _error;

  DocumentConversionService get _service =>
      widget.service ?? DocumentConversionService();

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
      title: const Text('Convert files to PDF'),
      description: const Text(
        'Create local PDFs from images, text, Markdown, and Office documents.',
      ),
      actions: <Widget>[
        ShadButton.outline(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _files.isNotEmpty && !_busy ? _convert : null,
          child: Text(_busy ? 'Converting…' : 'Convert'),
        ),
      ],
      child: SizedBox(
        width: 620,
        height: 410,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ShadButton.outline(
                  leading: const Icon(LucideIcons.filePlus2, size: 15),
                  onPressed: _busy ? null : _addFiles,
                  child: const Text('Add files'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _files.isEmpty
                        ? 'PNG, JPG, WEBP, TXT, MD, DOCX, PPTX, or XLSX'
                        : '${_files.length} ${_files.length == 1 ? 'file' : 'files'} selected',
                    style: const TextStyle(
                      color: WorkspaceColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: WorkspaceColors.panelRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WorkspaceColors.border),
                ),
                child: _files.isEmpty
                    ? const Center(
                        child: Text(
                          'Add one or more files to create a PDF for each.',
                          style: TextStyle(
                            color: WorkspaceColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _files.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (BuildContext context, int index) {
                          final String source = _files[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: WorkspaceColors.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: WorkspaceColors.border),
                            ),
                            child: Row(
                              children: <Widget>[
                                const Icon(
                                  LucideIcons.fileText,
                                  size: 15,
                                  color: WorkspaceColors.textMuted,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        path.basename(source),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: WorkspaceColors.textStrong,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        source,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: WorkspaceColors.textFaint,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: Key('convert-remove-$index'),
                                  tooltip: 'Remove ${path.basename(source)}',
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _files.removeAt(index);
                                          _error = null;
                                        }),
                                  icon: const Icon(LucideIcons.x, size: 15),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: WorkspaceColors.warning,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addFiles() async {
    final List<String> selected =
        await (widget.pickSources ?? _pickConversionSources)();
    if (!mounted || selected.isEmpty) {
      return;
    }
    setState(() {
      for (final String source in selected) {
        if (!_files.contains(source)) {
          _files.add(source);
        }
      }
      _error = null;
    });
  }

  Future<void> _convert() async {
    final String? outputDirectory =
        await (widget.pickOutputDirectory ?? _pickConversionOutputDirectory)();
    if (!mounted || outputDirectory == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<UtilityResult> results = await _service.convert(
        List<String>.unmodifiable(_files),
        outputDirectory,
      );
      await _complete(results);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _complete(List<UtilityResult> results) async {
    final ConversionCompleted? callback = widget.onCompleted;
    if (callback != null) {
      await callback(results);
      return;
    }
    for (final UtilityResult result in results) {
      await ref
          .read(workspaceNotifierProvider.notifier)
          .openUtilityResult(result);
    }
  }
}

class CombinePdfDialog extends ConsumerStatefulWidget {
  const CombinePdfDialog({
    this.service,
    this.pickSources,
    this.pickDestination,
    this.onCompleted,
    super.key,
  });

  final PdfUtilityService? service;
  final PickPdfSources? pickSources;
  final PickPdfDestination? pickDestination;
  final UtilityCompleted? onCompleted;

  @override
  ConsumerState<CombinePdfDialog> createState() => _CombinePdfDialogState();
}

class _CombinePdfDialogState extends ConsumerState<CombinePdfDialog> {
  final List<String> _files = <String>[];
  bool _busy = false;
  String? _error;

  PdfUtilityService get _service =>
      widget.service ?? ref.read(pdfUtilityServiceProvider);

  void _move(int from, int to) {
    if (from == to || to < 0 || to >= _files.length) {
      return;
    }
    setState(() {
      final String source = _files.removeAt(from);
      _files.insert(to, source);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
      title: const Text('Combine PDF files'),
      description: const Text(
        'Add two or more PDFs, then arrange them in output order.',
      ),
      actions: <Widget>[
        ShadButton.outline(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: _files.length >= 2 && !_busy ? _combine : null,
          child: Text(_busy ? 'Combining…' : 'Combine'),
        ),
      ],
      child: SizedBox(
        width: 620,
        height: 410,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ShadButton.outline(
                  leading: const Icon(LucideIcons.files, size: 15),
                  onPressed: _busy ? null : _addPdfs,
                  child: const Text('Add PDFs'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _files.isEmpty
                        ? 'No PDFs selected'
                        : '${_files.length} PDFs selected',
                    style: const TextStyle(
                      color: WorkspaceColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: WorkspaceColors.panelRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: WorkspaceColors.border),
                ),
                child: _files.isEmpty
                    ? const Center(
                        child: Text(
                          'Add PDFs to create an ordered output.',
                          style: TextStyle(
                            color: WorkspaceColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        key: const Key('combine-selected-files'),
                        padding: const EdgeInsets.all(8),
                        buildDefaultDragHandles: false,
                        itemCount: _files.length,
                        onReorderItem: _move,
                        itemBuilder: (BuildContext context, int index) {
                          final String source = _files[index];
                          return _CombineSourceTile(
                            key: ValueKey<String>(source),
                            index: index,
                            source: source,
                            canMoveUp: index > 0,
                            canMoveDown: index < _files.length - 1,
                            onMoveUp: () => _move(index, index - 1),
                            onMoveDown: () => _move(index, index + 1),
                            onRemove: () => setState(() {
                              _files.removeAt(index);
                              _error = null;
                            }),
                          );
                        },
                      ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: WorkspaceColors.warning,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addPdfs() async {
    final List<String> selected =
        await (widget.pickSources ?? _pickMultiplePdfs)();
    if (!mounted || selected.isEmpty) {
      return;
    }
    setState(() {
      for (final String source in selected) {
        if (!_files.contains(source)) {
          _files.add(source);
        }
      }
      _error = null;
    });
  }

  Future<void> _combine() async {
    final String? destination =
        await (widget.pickDestination ?? _pickCombinedPdfDestination)();
    if (!mounted || destination == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final UtilityResult result = await _service.combine(
        sources: List<String>.unmodifiable(_files),
        outputPath: destination,
      );
      await _complete(result);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _complete(UtilityResult result) async {
    final UtilityCompleted? callback = widget.onCompleted;
    if (callback != null) {
      await callback(result);
      return;
    }
    await ref
        .read(workspaceNotifierProvider.notifier)
        .openUtilityResult(result);
  }
}

class _CombineSourceTile extends StatelessWidget {
  const _CombineSourceTile({
    required this.index,
    required this.source,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    super.key,
  });

  final int index;
  final String source;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('combine-file-$index'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: WorkspaceColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WorkspaceColors.border),
      ),
      child: Row(
        children: <Widget>[
          ReorderableDragStartListener(
            key: Key('combine-drag-$index'),
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                LucideIcons.gripVertical,
                size: 15,
                color: WorkspaceColors.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  path.basename(source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WorkspaceColors.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WorkspaceColors.textFaint,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('combine-move-up-$index'),
            tooltip: 'Move ${path.basename(source)} up',
            onPressed: canMoveUp ? onMoveUp : null,
            icon: const Icon(LucideIcons.arrowUp, size: 15),
          ),
          IconButton(
            key: Key('combine-move-down-$index'),
            tooltip: 'Move ${path.basename(source)} down',
            onPressed: canMoveDown ? onMoveDown : null,
            icon: const Icon(LucideIcons.arrowDown, size: 15),
          ),
          IconButton(
            key: Key('combine-remove-$index'),
            tooltip: 'Remove ${path.basename(source)}',
            onPressed: onRemove,
            icon: const Icon(LucideIcons.x, size: 15),
          ),
        ],
      ),
    );
  }
}

class ExtractPagesDialog extends ConsumerStatefulWidget {
  const ExtractPagesDialog({
    this.service,
    this.pickSource,
    this.pickDestination,
    this.loadPageCount,
    this.onCompleted,
    super.key,
  });

  final PdfUtilityService? service;
  final PickPdfSource? pickSource;
  final PickPdfDestination? pickDestination;
  final LoadPdfPageCount? loadPageCount;
  final UtilityCompleted? onCompleted;

  @override
  ConsumerState<ExtractPagesDialog> createState() => _ExtractPagesDialogState();
}

class _ExtractPagesDialogState extends ConsumerState<ExtractPagesDialog> {
  final TextEditingController _pages = TextEditingController();
  String? _source;
  int? _pageCount;
  bool _loadingSource = false;
  bool _busy = false;
  String? _operationError;

  PdfUtilityService get _service =>
      widget.service ?? ref.read(pdfUtilityServiceProvider);

  PdfPageSelection? get _selection {
    final int? pageCount = _pageCount;
    if (pageCount == null || _pages.text.trim().isEmpty) {
      return null;
    }
    try {
      return PdfPageSelection.parse(_pages.text, pageCount: pageCount);
    } on FormatException {
      return null;
    }
  }

  String? get _selectionError {
    final int? pageCount = _pageCount;
    if (pageCount == null || _pages.text.trim().isEmpty) {
      return null;
    }
    try {
      PdfPageSelection.parse(_pages.text, pageCount: pageCount);
      return null;
    } on FormatException catch (error) {
      return error.message.toString();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final PdfPageSelection? selection = _selection;
    return ShadDialog(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
      title: const Text('Extract PDF pages'),
      description: const Text(
        'Choose one PDF and enter pages or ranges in the order you need.',
      ),
      actions: <Widget>[
        ShadButton.outline(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          onPressed: selection != null && !_busy ? _extract : null,
          child: Text(_busy ? 'Extracting…' : 'Extract'),
        ),
      ],
      child: SizedBox(
        width: 560,
        height: 330,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ShadButton.outline(
                  leading: const Icon(LucideIcons.fileSearch, size: 15),
                  onPressed: _loadingSource || _busy ? null : _selectSource,
                  child: Text(_source == null ? 'Select PDF' : 'Change PDF'),
                ),
                const SizedBox(width: 12),
                if (_loadingSource)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_source != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          path.basename(_source!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WorkspaceColors.textStrong,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$_pageCount pages',
                          style: const TextStyle(
                            color: WorkspaceColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Pages',
              style: TextStyle(
                color: WorkspaceColors.textStrong,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const Key('extract-page-selection'),
              controller: _pages,
              enabled: _pageCount != null && !_busy,
              onChanged: (_) => setState(() => _operationError = null),
              decoration: const InputDecoration(
                hintText: 'For example: 1-3, 7, 9-11',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selection != null
                  ? '${selection.pages.length} ${selection.pages.length == 1 ? 'page' : 'pages'} selected'
                  : _selectionError ??
                        'Ranges are inclusive and pages keep the written order.',
              style: TextStyle(
                color: _selectionError == null
                    ? WorkspaceColors.textMuted
                    : WorkspaceColors.warning,
                fontSize: 11.5,
              ),
            ),
            if (_operationError != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _operationError!,
                style: const TextStyle(
                  color: WorkspaceColors.warning,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectSource() async {
    final String? source = await (widget.pickSource ?? _pickSinglePdf)();
    if (!mounted || source == null) {
      return;
    }
    setState(() {
      _source = source;
      _pageCount = null;
      _loadingSource = true;
      _operationError = null;
      _pages.clear();
    });
    try {
      final int pageCount = await (widget.loadPageCount ?? _readPdfPageCount)(
        source,
      );
      if (pageCount < 1) {
        throw const FormatException('The selected PDF has no pages.');
      }
      if (mounted && _source == source) {
        setState(() => _pageCount = pageCount);
      }
    } catch (error) {
      if (mounted && _source == source) {
        setState(() {
          _source = null;
          _pageCount = null;
          _loadingSource = false;
          _operationError =
              'Could not load ${path.basename(source)}: ${_messageFor(error)}';
        });
      }
    } finally {
      if (mounted && _source == source) {
        setState(() => _loadingSource = false);
      }
    }
  }

  Future<void> _extract() async {
    final String? source = _source;
    final PdfPageSelection? selection = _selection;
    if (source == null || selection == null) {
      return;
    }
    final String? destination =
        await (widget.pickDestination ?? _pickExtractedPdfDestination)();
    if (!mounted || destination == null) {
      return;
    }
    setState(() {
      _busy = true;
      _operationError = null;
    });
    try {
      final UtilityResult result = await _service.extract(
        sourcePath: source,
        pages: selection.pages,
        outputPath: destination,
      );
      await _complete(result);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _operationError = _messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _complete(UtilityResult result) async {
    final UtilityCompleted? callback = widget.onCompleted;
    if (callback != null) {
      await callback(result);
      return;
    }
    await ref
        .read(workspaceNotifierProvider.notifier)
        .openUtilityResult(result);
  }
}

Future<List<String>> _pickMultiplePdfs() async {
  final FilePickerResult? result = await FilePicker.pickFiles(
    dialogTitle: 'Add PDFs to combine',
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
    allowMultiple: true,
    lockParentWindow: true,
  );
  return result?.files
          .map((PlatformFile file) => file.path)
          .whereType<String>()
          .toList(growable: false) ??
      const <String>[];
}

Future<String?> _pickSinglePdf() async {
  final FilePickerResult? result = await FilePicker.pickFiles(
    dialogTitle: 'Select a PDF to extract',
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
    allowMultiple: false,
    lockParentWindow: true,
  );
  return result?.files.single.path;
}

Future<String?> _pickExportPdf() async {
  final FilePickerResult? result = await FilePicker.pickFiles(
    dialogTitle: 'Select a PDF to export',
    type: FileType.custom,
    allowedExtensions: const <String>['pdf'],
    allowMultiple: false,
    lockParentWindow: true,
  );
  return result?.files.single.path;
}

Future<String?> _pickCombinedPdfDestination() => FilePicker.saveFile(
  dialogTitle: 'Save combined PDF',
  fileName: 'combined.pdf',
  type: FileType.custom,
  allowedExtensions: const <String>['pdf'],
  lockParentWindow: true,
);

Future<String?> _pickExtractedPdfDestination() => FilePicker.saveFile(
  dialogTitle: 'Save extracted pages',
  fileName: 'extracted-pages.pdf',
  type: FileType.custom,
  allowedExtensions: const <String>['pdf'],
  lockParentWindow: true,
);

Future<String?> _pickExportDestination(
  UtilityFormat format,
  String sourcePath,
) {
  final String extension = switch (format) {
    UtilityFormat.markdown => 'md',
    UtilityFormat.word => 'docx',
    UtilityFormat.powerpoint => 'pptx',
    _ => throw ArgumentError.value(format),
  };
  return FilePicker.saveFile(
    dialogTitle: 'Save exported document',
    fileName: '${path.basenameWithoutExtension(sourcePath)}.$extension',
    type: FileType.custom,
    allowedExtensions: <String>[extension],
    lockParentWindow: true,
  );
}

Future<List<String>> _pickConversionSources() async {
  final FilePickerResult? result = await FilePicker.pickFiles(
    dialogTitle: 'Select files to convert to PDF',
    type: FileType.custom,
    allowedExtensions: DocumentConversionService.supportedExtensions
        .map((String extension) => extension.substring(1))
        .toList(growable: false),
    allowMultiple: true,
    lockParentWindow: true,
  );
  return result?.files
          .map((PlatformFile file) => file.path)
          .whereType<String>()
          .toList(growable: false) ??
      const <String>[];
}

Future<String?> _pickConversionOutputDirectory() => FilePicker.getDirectoryPath(
  dialogTitle: 'Choose a folder for converted PDFs',
  lockParentWindow: true,
);

Future<int> _readPdfPageCount(String sourcePath) async {
  final PdfDocument document = await PdfDocument.openFile(sourcePath);
  try {
    return document.pages.length;
  } finally {
    await document.dispose();
  }
}

String _messageFor(Object error) {
  if (error is UtilityFailure) {
    return error.message;
  }
  if (error is FormatException) {
    return error.message.toString();
  }
  return error.toString();
}
