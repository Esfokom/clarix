import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import '../../../utilities/domain/utility_job.dart';
import '../../../utilities/infrastructure/document_conversion_service.dart';
import '../../../utilities/infrastructure/pdf_export_service.dart';
import '../../application/workspace_providers.dart';
import 'workspace_common.dart';
import 'pdf_combine_extract_dialogs.dart';

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
typedef RunPdfExport =
    Future<UtilityResult> Function({
      required String sourcePath,
      required UtilityFormat format,
      required String outputPath,
    });

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
    this.runExport,
    this.onCompleted,
    super.key,
  });

  final PdfExportService? service;
  final PickPdfSource? pickSource;
  final PickExportDestination? pickDestination;
  final RunPdfExport? runExport;
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
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
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
                      style: TextStyle(
                        color: colors.textStrong,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              'Output format',
              style: TextStyle(
                color: colors.textStrong,
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
                    colors: colors,
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
                    colors: colors,
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
                    colors: colors,
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
                color: colors.panelRaised,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: colors.accentBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(LucideIcons.info, size: 15, color: colors.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Word and PowerPoint are visual exports. They preserve each PDF page as an image and add extracted text for search and accessibility, but do not recreate editable page layouts.',
                      style: TextStyle(
                        color: colors.textMuted,
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
                style: TextStyle(color: colors.warning, fontSize: 12),
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
    final String? source = await (widget.pickSource ?? pickExportPdf)();
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
        await (widget.pickDestination ?? pickExportDestination)(
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
      final RunPdfExport? runExport = widget.runExport;
      final UtilityResult result = runExport != null
          ? await runExport(
              sourcePath: source,
              format: _format,
              outputPath: destination,
            )
          : await _service.export(
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
        setState(() => _error = utilityMessageFor(error));
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
    required this.colors,
    super.key,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          height: 84,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected ? colors.accentSoft : colors.panel,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? colors.accent : colors.border,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: colors.textStrong,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
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
    final WorkspaceSurfaceTokens colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
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
                    style: TextStyle(color: colors.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colors.panelRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: _files.isEmpty
                    ? Center(
                        child: Text(
                          'Add one or more files to create a PDF for each.',
                          style: TextStyle(
                            color: colors.textMuted,
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
                              color: colors.panel,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.border),
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  LucideIcons.fileText,
                                  size: 15,
                                  color: colors.textMuted,
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
                                        style: TextStyle(
                                          color: colors.textStrong,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        source,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.textFaint,
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
                style: TextStyle(color: colors.warning, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addFiles() async {
    final List<String> selected =
        await (widget.pickSources ?? pickConversionSources)();
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
        await (widget.pickOutputDirectory ?? pickConversionOutputDirectory)();
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
        setState(() => _error = utilityMessageFor(error));
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
