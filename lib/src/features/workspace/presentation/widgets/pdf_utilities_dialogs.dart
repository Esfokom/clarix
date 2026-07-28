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
import '../../application/workspace_providers.dart';
import 'workspace_common.dart';

typedef PickPdfSources = Future<List<String>> Function();
typedef PickPdfSource = Future<String?> Function();
typedef PickPdfDestination = Future<String?> Function();
typedef LoadPdfPageCount = Future<int> Function(String sourcePath);
typedef UtilityCompleted = FutureOr<void> Function(UtilityResult result);

Future<void> showCombinePdfDialog(BuildContext context) => showShadDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const CombinePdfDialog(),
);

Future<void> showExtractPagesDialog(BuildContext context) =>
    showShadDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExtractPagesDialog(),
    );

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
        setState(() => _operationError = _messageFor(error));
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
