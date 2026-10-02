import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/services/local/app_paths.dart';
import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/providers/pdf_rasterizer_provider.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../domain/use_cases/detect_page_anomalies_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../view_models/page_review_view_model.dart';
import 'export_convert_sheet.dart';

class PageReviewScreen extends StatefulWidget {
  const PageReviewScreen({super.key, required this.projectId, this.viewModel});

  final String projectId;

  /// Injectable for widget tests; production code leaves this null.
  final PageReviewViewModel? viewModel;

  @override
  State<PageReviewScreen> createState() => _PageReviewScreenState();
}

class _PageReviewScreenState extends State<PageReviewScreen> {
  late final PageReviewViewModel _viewModel;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        PageReviewViewModel(
          projectId: widget.projectId,
          pageRepository: locator<PageRepository>(),
          detectAnomaliesUseCase: locator<DetectPageAnomaliesUseCase>(),
          capturePageUseCase: locator<CapturePageUseCase>(),
        );
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  int _nextSequence() {
    if (_viewModel.pages.isEmpty) return 0;
    return _viewModel.pages.map((p) => p.sequence).reduce(math.max) + 1;
  }

  Future<void> _openCamera() async {
    if (_importing || !mounted) return;
    context.push(AppRoutes.captureFor(widget.projectId));
  }

  Future<void> _importFromGallery() async {
    if (_importing) return;
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    await _appendImagePaths(
      files.map((f) => f.path).toList(),
      providerName: 'gallery-import',
    );
  }

  Future<void> _importFromFiles() async {
    if (_importing) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final useCase = locator<CapturePageUseCase>();
      final paths = locator<AppPaths>();
      const info = ProviderInfo(
        providerName: 'pdf-import',
        adapterVersion: '1.0.0',
      );
      var sequence = _nextSequence();
      await for (final page in locator<PdfRasterizerProvider>().rasterize(
        path,
      )) {
        final dest = paths.originalPathFor(const Uuid().v4(), ext: 'png');
        await File(dest).writeAsBytes(page.pngBytes);
        await useCase.processCapture(
          capture: StillCapture(
            originalImagePath: dest,
            detectedQuad: null,
            qualityScore: 0.8,
            warnings: const {},
            capturedAtMs: DateTime.now().millisecondsSinceEpoch,
            providerInfo: info,
          ),
          projectId: widget.projectId,
          sequence: sequence,
          keepOriginal: true,
        );
        sequence++;
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _appendImagePaths(
    List<String> paths, {
    required String providerName,
  }) async {
    if (_importing || paths.isEmpty) return;
    setState(() => _importing = true);
    try {
      final useCase = locator<CapturePageUseCase>();
      final info = ProviderInfo(
        providerName: providerName,
        adapterVersion: '1.0.0',
      );
      var sequence = _nextSequence();
      for (final path in paths) {
        await useCase.processCapture(
          capture: StillCapture(
            originalImagePath: path,
            detectedQuad: null,
            qualityScore: 0.8,
            warnings: const {},
            capturedAtMs: DateTime.now().millisecondsSinceEpoch,
            providerInfo: info,
          ),
          projectId: widget.projectId,
          sequence: sequence,
          keepOriginal: true,
        );
        sequence++;
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openExportSheet() async {
    if (_viewModel.pages.isEmpty) return;
    final launch = await showModalBottomSheet<ExportLaunch>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10241C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) =>
          Theme(data: AppTheme.homeShell(), child: const ExportConvertSheet()),
    );
    if (launch == null || !mounted) return;
    context.push(AppRoutes.exportFor(widget.projectId), extra: launch);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.homeBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Theme(
        data: AppTheme.homeShell(),
        child: Scaffold(
          backgroundColor: AppTheme.homeBackground,
          appBar: AppBar(
            title: Text(l10n.reviewTitle),
            actions: [
              ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => IconButton(
                  key: const ValueKey('reviewToggleGridButton'),
                  tooltip: l10n.toggleGridView,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.homeIconWell,
                    foregroundColor: AppTheme.accent,
                  ),
                  icon: Icon(
                    _viewModel.gridView
                        ? LucideIcons.layoutGrid
                        : LucideIcons.list,
                  ),
                  onPressed: _viewModel.toggleGridView,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            children: [
              ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) {
                  if (_viewModel.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_viewModel.pages.isEmpty) {
                    return Center(child: Text(l10n.pagesScanned(0)));
                  }

                  VoidCallback onCropFor(ScanPage page) =>
                      () => context.push(
                        AppRoutes.cropCorrectionFor(widget.projectId, page.id),
                      );
                  VoidCallback onAdjustFor(ScanPage page) =>
                      () => context.push(
                        AppRoutes.filterAdjustmentFor(
                          widget.projectId,
                          page.id,
                        ),
                      );
                  VoidCallback onOcrFor(ScanPage page) =>
                      () => context.push(
                        AppRoutes.ocrReviewFor(widget.projectId, page.id),
                      );
                  VoidCallback onResplitFor(ScanPage page) =>
                      () => context.push(
                        AppRoutes.spreadSplitFor(widget.projectId, page.id),
                      );
                  VoidCallback onRescanFor(ScanPage page) =>
                      () => context.push(
                        AppRoutes.captureFor(widget.projectId),
                        extra: page.id,
                      );
                  Future<void> onPageLabelFor(ScanPage page) async {
                    final label = await showTextInputDialog(
                      context: context,
                      title: l10n.pageLabelTitle,
                      label: l10n.pageLabelHint,
                      initialText: page.logicalPageLabel ?? '',
                      cancelLabel: l10n.cancel,
                      saveLabel: l10n.save,
                    );
                    if (!mounted || label == null) return;
                    await _viewModel.setLogicalPageLabel(page, label);
                  }

                  VoidCallback onPreviewFor(ScanPage page, int index) =>
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _PagePreviewScreen(
                            page: page,
                            index: index,
                            l10n: l10n,
                            onRotate: () => _viewModel.rotate(page),
                            onDuplicate: () => _viewModel.duplicate(page),
                            onDelete: () => _viewModel.delete(page),
                            onRevert: () => _viewModel.revertToOriginal(page),
                            onRescan: onRescanFor(page),
                            onCrop: onCropFor(page),
                            onAdjust: onAdjustFor(page),
                            onOcr: onOcrFor(page),
                            onResplit: onResplitFor(page),
                            onPageLabel: () => onPageLabelFor(page),
                          ),
                        ),
                      );

                  if (_viewModel.gridView) {
                    return GridView.builder(
                      key: const ValueKey('pageReviewGrid'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                      itemCount: _viewModel.pages.length,
                      itemBuilder: (context, index) {
                        final page = _viewModel.pages[index];
                        return _PageGridTile(
                          key: ValueKey('page-${page.id}'),
                          page: page,
                          index: index,
                          l10n: l10n,
                          selected: _viewModel.selectedIds.contains(page.id),
                          selectionMode: _viewModel.selectedIds.isNotEmpty,
                          onTap: _viewModel.selectedIds.isNotEmpty
                              ? () => _viewModel.toggleSelected(page.id)
                              : onPreviewFor(page, index),
                          onLongPress: () => _viewModel.toggleSelected(page.id),
                          onRotate: () => _viewModel.rotate(page),
                          onDuplicate: () => _viewModel.duplicate(page),
                          onDelete: () => _viewModel.delete(page),
                          onRevert: () => _viewModel.revertToOriginal(page),
                          onRescan: onRescanFor(page),
                          onCrop: onCropFor(page),
                          onAdjust: onAdjustFor(page),
                          onOcr: onOcrFor(page),
                          onResplit: onResplitFor(page),
                          onPageLabel: () => onPageLabelFor(page),
                        );
                      },
                    );
                  }

                  return ReorderableListView.builder(
                    key: const ValueKey('pageReviewList'),
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _viewModel.pages.length,
                    onReorder: _viewModel.reorder,
                    itemBuilder: (context, index) {
                      final page = _viewModel.pages[index];
                      return _PageTile(
                        key: ValueKey('page-${page.id}'),
                        page: page,
                        index: index,
                        l10n: l10n,
                        selected: _viewModel.selectedIds.contains(page.id),
                        selectionMode: _viewModel.selectedIds.isNotEmpty,
                        onTap: _viewModel.selectedIds.isNotEmpty
                            ? () => _viewModel.toggleSelected(page.id)
                            : onPreviewFor(page, index),
                        onLongPress: () => _viewModel.toggleSelected(page.id),
                        onRotate: () => _viewModel.rotate(page),
                        onDuplicate: () => _viewModel.duplicate(page),
                        onDelete: () => _viewModel.delete(page),
                        onRevert: () => _viewModel.revertToOriginal(page),
                        onRescan: onRescanFor(page),
                        onCrop: onCropFor(page),
                        onAdjust: onAdjustFor(page),
                        onOcr: onOcrFor(page),
                        onResplit: onResplitFor(page),
                        onPageLabel: () => onPageLabelFor(page),
                        onDismissDuplicate: () =>
                            _viewModel.dismissWarning(page, 'duplicate'),
                        onDismissMissing: () =>
                            _viewModel.dismissWarning(page, 'missing'),
                      );
                    },
                  );
                },
              ),
              ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) {
                  if (!_importing) return const SizedBox.shrink();
                  return const ColoredBox(
                    color: Color(0x8804100C),
                    child: Center(
                      child: CircularProgressIndicator(
                        key: ValueKey('reviewImporting'),
                        color: AppTheme.accent,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) {
                  final selected = _viewModel.selectedIds.length;
                  final canExport = _viewModel.pages.isNotEmpty && !_importing;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: 8,
                          left: 4,
                          right: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selected == 0
                                    ? l10n.pagesScanned(_viewModel.pages.length)
                                    : l10n.selectedCount(selected),
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  color: AppTheme.homeMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (selected > 0) ...[
                              IconButton(
                                key: const ValueKey('reviewSelectionCancel'),
                                onPressed: _viewModel.clearSelection,
                                icon: const Icon(
                                  LucideIcons.x,
                                  color: AppTheme.homeIcon,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('reviewSelectionRotate'),
                                onPressed: _viewModel.rotateSelected,
                                icon: const Icon(
                                  LucideIcons.rotateCw,
                                  color: AppTheme.homeIcon,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('reviewSelectionDuplicate'),
                                onPressed: _viewModel.duplicateSelected,
                                icon: const Icon(
                                  LucideIcons.copy,
                                  color: AppTheme.homeIcon,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('reviewSelectionDelete'),
                                onPressed: _viewModel.deleteSelected,
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  color: Color(0xFFE05353),
                                  size: 18,
                                ),
                              ),
                            ] else
                              TextButton.icon(
                                key: const ValueKey('reviewPageOrderButton'),
                                onPressed: _viewModel.gridView
                                    ? _viewModel.toggleGridView
                                    : null,
                                icon: const Icon(
                                  LucideIcons.arrowUpDown,
                                  size: 16,
                                  color: AppTheme.accent,
                                ),
                                label: Text(
                                  l10n.reviewPageOrder,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _ReviewAddAction(
                                key: const ValueKey('reviewAddCamera'),
                                icon: LucideIcons.camera,
                                label: l10n.reviewAddCamera,
                                onPressed: _importing ? null : _openCamera,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ReviewAddAction(
                                key: const ValueKey('reviewAddGallery'),
                                icon: LucideIcons.image,
                                label: l10n.reviewAddGallery,
                                onPressed: _importing
                                    ? null
                                    : _importFromGallery,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ReviewAddAction(
                                key: const ValueKey('reviewAddFromFiles'),
                                icon: LucideIcons.fileUp,
                                label: l10n.reviewAddFromFiles,
                                onPressed: _importing ? null : _importFromFiles,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: canExport
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.accent,
                                    AppTheme.accentDeep,
                                  ],
                                )
                              : null,
                          color: canExport ? null : AppTheme.homeCard,
                        ),
                        child: FilledButton.icon(
                          key: const ValueKey('reviewExportButton'),
                          onPressed: canExport ? _openExportSheet : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: const Color(0xFF04140C),
                            disabledForegroundColor: AppTheme.homeMuted,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          icon: const Icon(LucideIcons.share, size: 18),
                          label: Text(
                            l10n.reviewExportConvert,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewAddAction extends StatelessWidget {
  const _ReviewAddAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? AppTheme.accent : AppTheme.homeMuted;
    return Material(
      color: AppTheme.homeCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.homeHairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: enabled ? AppTheme.homeText : AppTheme.homeMuted,
                  fontSize: 11,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageMenuButton extends StatelessWidget {
  const _PageMenuButton({
    required this.page,
    required this.l10n,
    required this.onCrop,
    required this.onAdjust,
    required this.onOcr,
    required this.onResplit,
    required this.onPageLabel,
    required this.onRotate,
    required this.onDuplicate,
    required this.onRevert,
    required this.onDelete,
    required this.onRescan,
    this.lightIcon = false,
  });

  final ScanPage page;
  final AppLocalizations l10n;
  final VoidCallback onCrop;
  final VoidCallback onAdjust;
  final VoidCallback onOcr;
  final VoidCallback onResplit;
  final VoidCallback onPageLabel;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onRevert;
  final VoidCallback onDelete;
  final VoidCallback onRescan;
  final bool lightIcon;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey('pageMenu-${page.id}'),
      padding: EdgeInsets.zero,
      icon: Icon(
        LucideIcons.ellipsisVertical,
        color: lightIcon ? Colors.white : AppTheme.homeIcon,
        size: 18,
      ),
      onSelected: (action) {
        switch (action) {
          case 'crop':
            onCrop();
          case 'adjust':
            onAdjust();
          case 'ocr':
            onOcr();
          case 'resplit':
            onResplit();
          case 'label':
            onPageLabel();
          case 'rotate':
            onRotate();
          case 'duplicate':
            onDuplicate();
          case 'revert':
            onRevert();
          case 'delete':
            onDelete();
          case 'rescan':
            onRescan();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'crop', child: Text(l10n.cropAction)),
        PopupMenuItem(value: 'adjust', child: Text(l10n.adjustAction)),
        PopupMenuItem(value: 'ocr', child: Text(l10n.ocrAction)),
        if (page.spreadSiblingPageId != null)
          PopupMenuItem(value: 'resplit', child: Text(l10n.spreadSplitAction)),
        PopupMenuItem(value: 'label', child: Text(l10n.pageLabelAction)),
        PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
        PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
        PopupMenuItem(value: 'revert', child: Text(l10n.revertToOriginal)),
        PopupMenuItem(value: 'rescan', child: Text(l10n.rescan)),
        PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.page,
    required this.index,
    required this.l10n,
    required this.onRotate,
    required this.onDuplicate,
    required this.onDelete,
    required this.onRevert,
    required this.onRescan,
    required this.onCrop,
    required this.onAdjust,
    required this.onOcr,
    required this.onResplit,
    required this.onPageLabel,
    this.onDismissDuplicate,
    this.onDismissMissing,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  final ScanPage page;
  final int index;
  final AppLocalizations l10n;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onRevert;
  final VoidCallback onRescan;
  final VoidCallback onCrop;
  final VoidCallback onAdjust;
  final VoidCallback onOcr;
  final VoidCallback onResplit;
  final VoidCallback onPageLabel;
  final VoidCallback? onDismissDuplicate;
  final VoidCallback? onDismissMissing;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final thumb =
        page.processedImagePath ?? page.thumbnailPath ?? page.originalImagePath;
    final hasThumb = File(thumb).existsSync();
    final sizeLabel = hasThumb ? _formatBytes(File(thumb).lengthSync()) : null;
    final title = page.logicalPageLabel ?? l10n.reviewPageLabel(index + 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.homeCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.homeHairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(
                children: [
                  if (selectionMode)
                    Checkbox(
                      value: selected,
                      activeColor: AppTheme.accent,
                      onChanged: (_) => onTap?.call(),
                    ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 64,
                      child: hasThumb
                          ? _OpaquePageImage(
                              path: thumb,
                              rotationDegrees: page.rotationDegrees,
                            )
                          : const ColoredBox(color: Color(0xFF0B1612)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: AppTheme.homeText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sizeLabel != null)
                          Text(
                            sizeLabel,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: AppTheme.homeMuted,
                              fontSize: 12,
                            ),
                          ),
                        ?_buildWarnings(context),
                      ],
                    ),
                  ),
                  _PageMenuButton(
                    page: page,
                    l10n: l10n,
                    onCrop: onCrop,
                    onAdjust: onAdjust,
                    onOcr: onOcr,
                    onResplit: onResplit,
                    onPageLabel: onPageLabel,
                    onRotate: onRotate,
                    onDuplicate: onDuplicate,
                    onRevert: onRevert,
                    onDelete: onDelete,
                    onRescan: onRescan,
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        LucideIcons.gripVertical,
                        color: AppTheme.homeMuted,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildWarnings(BuildContext context) {
    final chips = <Widget>[];
    if (page.duplicateOfPageId != null &&
        !page.dismissedWarnings.contains('duplicate')) {
      chips.add(
        InputChip(
          key: ValueKey('dismissDuplicate-${page.id}'),
          label: Text(l10n.possibleDuplicate),
          onDeleted: onDismissDuplicate,
          deleteButtonTooltipMessage: l10n.dismissWarning,
        ),
      );
    }
    if (page.likelyMissingBefore &&
        !page.dismissedWarnings.contains('missing')) {
      chips.add(
        InputChip(
          key: ValueKey('dismissMissing-${page.id}'),
          label: Text(l10n.possibleMissingPage),
          onDeleted: onDismissMissing,
          deleteButtonTooltipMessage: l10n.dismissWarning,
        ),
      );
    }
    if (page.status == PageStatus.needsRescan) {
      chips.add(InputChip(label: Text(l10n.lowQuality)));
    }
    if (chips.isEmpty) return null;
    return Wrap(spacing: 4, runSpacing: 4, children: chips);
  }
}

/// Browse-only grid alternative to [_PageTile] (SPEC 6.3 thumbnail/list
/// views). `ReorderableListView` has no first-party grid equivalent in this
/// Flutter version, so drag-reorder stays List-view-only; every other page
/// action (rotate/duplicate/delete/crop/adjust/OCR/resplit/rescan) is still
/// reachable via the same popup menu.
class _PageGridTile extends StatelessWidget {
  const _PageGridTile({
    super.key,
    required this.page,
    required this.index,
    required this.l10n,
    required this.onRotate,
    required this.onDuplicate,
    required this.onDelete,
    required this.onRevert,
    required this.onRescan,
    required this.onCrop,
    required this.onAdjust,
    required this.onOcr,
    required this.onResplit,
    required this.onPageLabel,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
  });

  final ScanPage page;
  final int index;
  final AppLocalizations l10n;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onRevert;
  final VoidCallback onRescan;
  final VoidCallback onCrop;
  final VoidCallback onAdjust;
  final VoidCallback onOcr;
  final VoidCallback onResplit;
  final VoidCallback onPageLabel;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final thumb =
        page.processedImagePath ?? page.thumbnailPath ?? page.originalImagePath;
    final hasThumb = File(thumb).existsSync();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppTheme.accent : AppTheme.homeHairline,
          width: selected ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Material(
          color: const Color(0xFF12241C),
          surfaceTintColor: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.expand,
              children: [
                hasThumb
                    ? _OpaquePageImage(
                        path: thumb,
                        rotationDegrees: page.rotationDegrees,
                      )
                    : const ColoredBox(color: Color(0xFF0B1612)),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC04140C),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      page.logicalPageLabel ?? '${index + 1}',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (selectionMode)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? AppTheme.accent
                            : const Color(0x6604140C),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? AppTheme.accent : Colors.white70,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          LucideIcons.check,
                          size: 14,
                          color: selected
                              ? const Color(0xFF04140C)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC10241C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _PageMenuButton(
                      page: page,
                      l10n: l10n,
                      lightIcon: true,
                      onCrop: onCrop,
                      onAdjust: onAdjust,
                      onOcr: onOcr,
                      onResplit: onResplit,
                      onPageLabel: onPageLabel,
                      onRotate: onRotate,
                      onDuplicate: onDuplicate,
                      onRevert: onRevert,
                      onDelete: onDelete,
                      onRescan: onRescan,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen preview of the scanned (processed) page. Crop edits the
/// retained original; library/review always prefer processed.
class _PagePreviewScreen extends StatelessWidget {
  const _PagePreviewScreen({
    required this.page,
    required this.index,
    required this.l10n,
    required this.onRotate,
    required this.onDuplicate,
    required this.onDelete,
    required this.onRevert,
    required this.onRescan,
    required this.onCrop,
    required this.onAdjust,
    required this.onOcr,
    required this.onResplit,
    required this.onPageLabel,
  });

  final ScanPage page;
  final int index;
  final AppLocalizations l10n;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onRevert;
  final VoidCallback onRescan;
  final VoidCallback onCrop;
  final VoidCallback onAdjust;
  final VoidCallback onOcr;
  final VoidCallback onResplit;
  final VoidCallback onPageLabel;

  @override
  Widget build(BuildContext context) {
    final imagePath =
        page.processedImagePath ?? page.thumbnailPath ?? page.originalImagePath;
    final hasImage = File(imagePath).existsSync();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(page.logicalPageLabel ?? '#${index + 1}'),
        actions: [
          PopupMenuButton<String>(
            key: ValueKey('pagePreviewMenu-${page.id}'),
            onSelected: (action) {
              switch (action) {
                case 'crop':
                  onCrop();
                case 'adjust':
                  onAdjust();
                case 'ocr':
                  onOcr();
                case 'resplit':
                  onResplit();
                case 'label':
                  onPageLabel();
                case 'rotate':
                  onRotate();
                case 'duplicate':
                  onDuplicate();
                case 'revert':
                  onRevert();
                case 'delete':
                  Navigator.of(context).pop();
                  onDelete();
                case 'rescan':
                  onRescan();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'crop', child: Text(l10n.cropAction)),
              PopupMenuItem(value: 'adjust', child: Text(l10n.adjustAction)),
              PopupMenuItem(value: 'ocr', child: Text(l10n.ocrAction)),
              if (page.spreadSiblingPageId != null)
                PopupMenuItem(
                  value: 'resplit',
                  child: Text(l10n.spreadSplitAction),
                ),
              PopupMenuItem(value: 'label', child: Text(l10n.pageLabelAction)),
              PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
              PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
              PopupMenuItem(
                value: 'revert',
                child: Text(l10n.revertToOriginal),
              ),
              PopupMenuItem(value: 'rescan', child: Text(l10n.rescan)),
              PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
            ],
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          key: const ValueKey('pagePreviewImage'),
          minScale: 1,
          maxScale: 4,
          child: hasImage
              ? _OpaquePageImage(
                  path: imagePath,
                  rotationDegrees: page.rotationDegrees,
                  fit: BoxFit.contain,
                )
              : const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 64,
                ),
        ),
      ),
    );
  }
}

/// Scanned pages, especially imported PNGs, can carry an alpha channel.
/// Drawing them over white keeps the paper opaque on the dark review theme.
class _OpaquePageImage extends StatelessWidget {
  const _OpaquePageImage({
    required this.path,
    required this.rotationDegrees,
    this.fit = BoxFit.cover,
  });

  final String path;
  final int rotationDegrees;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: rotationDegrees ~/ 90,
      child: ColoredBox(
        color: Colors.white,
        child: Image.file(
          File(path),
          fit: fit,
          gaplessPlayback: true,
          color: Colors.white,
          colorBlendMode: BlendMode.dstOver,
        ),
      ),
    );
  }
}
