import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/repositories/export_job_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/repositories/settings_repository.dart';
import '../../../../domain/use_cases/export_images_use_case.dart';
import '../../../../domain/use_cases/export_project_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/export_view_model.dart';
import 'export_job_status_views.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.projectId, this.viewModel});

  final String projectId;

  /// Injectable for widget tests; production code leaves this null.
  final ExportViewModel? viewModel;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ExportViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        ExportViewModel(
          projectId: widget.projectId,
          projectRepository: locator<ProjectRepository>(),
          exportJobRepository: locator<ExportJobRepository>(),
          exportProjectUseCase: locator<ExportProjectUseCase>(),
          settingsRepository: locator<SettingsRepository>(),
          exportImagesUseCase: locator<ExportImagesUseCase>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _startExport(ExportFormat format) async {
    final l10n = AppLocalizations.of(context);
    if (await _viewModel.needsLargeExportAcknowledgement()) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(
            l10n.largeExportAcknowledgement(_viewModel.pageCount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.continueToCapture),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _viewModel.startExport(format);
  }

  Future<void> _openCompressDialog() async {
    final l10n = AppLocalizations.of(context);
    var quality = _viewModel.pdfOptions.imageQuality;
    var estimate = await _viewModel.estimatePdfSizeBytes();
    if (!mounted) return;
    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.compressAction),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                key: const ValueKey('compressQualitySlider'),
                value: quality,
                min: 0.1,
                max: 1.0,
                label: l10n.compressQualityLabel,
                onChanged: (value) => setDialogState(() => quality = value),
                onChangeEnd: (value) async {
                  final next = await _viewModel.estimatePdfSizeBytesFor(value);
                  setDialogState(() => estimate = next);
                },
              ),
              Text(
                l10n.compressEstimatedSize(_formatBytes(estimate)),
                key: const ValueKey('compressEstimatedSizeText'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('compressApplyButton'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.apply),
            ),
          ],
        ),
      ),
    );
    if (applied == true) {
      _viewModel.setPdfOptions(
        PdfExportOptions(
          pageSize: _viewModel.pdfOptions.pageSize,
          orientation: _viewModel.pdfOptions.orientation,
          marginPoints: _viewModel.pdfOptions.marginPoints,
          imageQuality: quality,
          maxDimensionPx: _viewModel.pdfOptions.maxDimensionPx,
          searchable: _viewModel.pdfOptions.searchable,
          watermarkText: _viewModel.pdfOptions.watermarkText,
          password: _viewModel.pdfOptions.password,
          ownerPassword: _viewModel.pdfOptions.ownerPassword,
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _exportImages(ImageExportFormat format) async {
    await _viewModel.exportImages(ImageExportOptions(format: format));
    final path = _viewModel.imagesOutputPath;
    if (path != null) {
      unawaited(SharePlus.instance.share(ShareParams(files: [XFile(path)])));
    }
  }

  Future<void> _openImagesFormatSheet() async {
    final l10n = AppLocalizations.of(context);
    final format = await showModalBottomSheet<ImageExportFormat>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('exportImagesJpg'),
              title: Text(l10n.exportImagesFormatJpg),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(ImageExportFormat.jpg),
            ),
            ListTile(
              key: const ValueKey('exportImagesPng'),
              title: Text(l10n.exportImagesFormatPng),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(ImageExportFormat.png),
            ),
          ],
        ),
      ),
    );
    if (format != null) await _exportImages(format);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.exportTitle),
        actions: [
          IconButton(
            key: const ValueKey('exportComposeButton'),
            icon: const Icon(Icons.auto_awesome_mosaic_outlined),
            tooltip: l10n.composeDocumentAction,
            onPressed: () =>
                context.push(AppRoutes.pageOperationsFor(widget.projectId)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          final job = _viewModel.job;
          if (_viewModel.exportingImages) {
            return const Center(child: CircularProgressIndicator());
          }
          if (job != null && job.status == ExportJobStatus.running) {
            return ExportProgressView(job: job, l10n: l10n);
          }
          if (job != null && job.status == ExportJobStatus.completed) {
            return ExportCompletedView(job: job, l10n: l10n);
          }
          if (job != null && job.status == ExportJobStatus.failed) {
            return ExportFailedView(
              job: job,
              l10n: l10n,
              onRetry: () => _viewModel.startExport(job.format),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PdfOptionsPanel(
                options: _viewModel.pdfOptions,
                l10n: l10n,
                onChanged: _viewModel.setPdfOptions,
              ),
              const SizedBox(height: 8),
              _FormatPicker(
                onSelected: _startExport,
                onCompress: _openCompressDialog,
                onExportImages: _openImagesFormatSheet,
                l10n: l10n,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PdfOptionsPanel extends StatelessWidget {
  const _PdfOptionsPanel({
    required this.options,
    required this.l10n,
    required this.onChanged,
  });

  final PdfExportOptions options;
  final AppLocalizations l10n;
  final ValueChanged<PdfExportOptions> onChanged;

  PdfExportOptions _copy({
    PdfPageSize? pageSize,
    PdfOrientation? orientation,
    double? marginPoints,
    String? watermarkText,
    bool clearWatermark = false,
  }) => PdfExportOptions(
    pageSize: pageSize ?? options.pageSize,
    orientation: orientation ?? options.orientation,
    marginPoints: marginPoints ?? options.marginPoints,
    imageQuality: options.imageQuality,
    maxDimensionPx: options.maxDimensionPx,
    searchable: options.searchable,
    password: options.password,
    ownerPassword: options.ownerPassword,
    watermarkText: clearWatermark
        ? null
        : (watermarkText ?? options.watermarkText),
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('pdfOptionsPanel'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.pdfOptionsSection,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.pdfPageSize),
              trailing: DropdownButton<PdfPageSize>(
                key: const ValueKey('pdfPageSizeDropdown'),
                value: options.pageSize,
                onChanged: (value) {
                  if (value != null) onChanged(_copy(pageSize: value));
                },
                items: [
                  DropdownMenuItem(
                    value: PdfPageSize.a4,
                    child: Text(l10n.pdfPageSizeA4),
                  ),
                  DropdownMenuItem(
                    value: PdfPageSize.letter,
                    child: Text(l10n.pdfPageSizeLetter),
                  ),
                  DropdownMenuItem(
                    value: PdfPageSize.legal,
                    child: Text(l10n.pdfPageSizeLegal),
                  ),
                  DropdownMenuItem(
                    value: PdfPageSize.matchSource,
                    child: Text(l10n.pdfPageSizeMatchSource),
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.pdfOrientation),
              trailing: DropdownButton<PdfOrientation>(
                key: const ValueKey('pdfOrientationDropdown'),
                value: options.orientation,
                onChanged: (value) {
                  if (value != null) onChanged(_copy(orientation: value));
                },
                items: [
                  DropdownMenuItem(
                    value: PdfOrientation.auto,
                    child: Text(l10n.pdfOrientationAuto),
                  ),
                  DropdownMenuItem(
                    value: PdfOrientation.portrait,
                    child: Text(l10n.pdfOrientationPortrait),
                  ),
                  DropdownMenuItem(
                    value: PdfOrientation.landscape,
                    child: Text(l10n.pdfOrientationLandscape),
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.pdfMargins),
              trailing: DropdownButton<double>(
                key: const ValueKey('pdfMarginsDropdown'),
                value: options.marginPoints,
                onChanged: (value) {
                  if (value != null) onChanged(_copy(marginPoints: value));
                },
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(l10n.pdfMarginsNone),
                  ),
                  DropdownMenuItem(
                    value: 18,
                    child: Text(l10n.pdfMarginsNarrow),
                  ),
                  DropdownMenuItem(
                    value: 36,
                    child: Text(l10n.pdfMarginsNormal),
                  ),
                ],
              ),
            ),
            _WatermarkField(
              initialText: options.watermarkText ?? '',
              label: l10n.pdfWatermark,
              hint: l10n.pdfWatermarkHint,
              onChanged: (value) {
                final trimmed = value.trim();
                onChanged(
                  _copy(
                    watermarkText: trimmed.isEmpty ? null : trimmed,
                    clearWatermark: trimmed.isEmpty,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WatermarkField extends StatefulWidget {
  const _WatermarkField({
    required this.initialText,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  final String initialText;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_WatermarkField> createState() => _WatermarkFieldState();
}

class _WatermarkFieldState extends State<_WatermarkField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('pdfWatermarkField'),
    controller: _controller,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
    ),
    onChanged: widget.onChanged,
  );
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({
    required this.onSelected,
    required this.onCompress,
    required this.onExportImages,
    required this.l10n,
  });

  final ValueChanged<ExportFormat> onSelected;
  final VoidCallback onCompress;
  final VoidCallback onExportImages;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FormatTile(
          key: const ValueKey('exportFormatImagePdf'),
          icon: Icons.picture_as_pdf_outlined,
          label: l10n.exportImagePdf,
          onTap: () => onSelected(ExportFormat.imagePdf),
          trailing: IconButton(
            key: const ValueKey('compressButtonImagePdf'),
            icon: const Icon(Icons.compress),
            tooltip: l10n.compressAction,
            onPressed: onCompress,
          ),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatSearchablePdf'),
          icon: Icons.picture_as_pdf,
          label: l10n.exportSearchablePdf,
          onTap: () => onSelected(ExportFormat.searchablePdf),
          trailing: IconButton(
            key: const ValueKey('compressButtonSearchablePdf'),
            icon: const Icon(Icons.compress),
            tooltip: l10n.compressAction,
            onPressed: onCompress,
          ),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatMarkdown'),
          icon: Icons.description_outlined,
          label: l10n.exportMarkdown,
          onTap: () => onSelected(ExportFormat.markdown),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatDocx'),
          icon: Icons.article_outlined,
          label: l10n.exportDocx,
          onTap: () => onSelected(ExportFormat.docx),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatImages'),
          icon: Icons.image_outlined,
          label: l10n.exportImages,
          onTap: onExportImages,
        ),
      ],
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
      trailing: trailing,
    ),
  );
}
