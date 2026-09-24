import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
import '../../../core/widgets/text_input_dialog.dart';
import '../view_models/page_review_view_model.dart';

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
        );
        sequence++;
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewTitle),
        actions: [
          ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => IconButton(
              key: const ValueKey('reviewToggleGridButton'),
              icon: Icon(
                _viewModel.gridView
                    ? Icons.view_list_outlined
                    : Icons.grid_view_outlined,
              ),
              tooltip: l10n.toggleGridView,
              onPressed: _viewModel.toggleGridView,
            ),
          ),
          ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => IconButton(
              key: const ValueKey('reviewExportButton'),
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: l10n.exportTitle,
              onPressed: _viewModel.pages.isEmpty
                  ? null
                  : () => context.push(AppRoutes.exportFor(widget.projectId)),
            ),
          ),
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
                    AppRoutes.filterAdjustmentFor(widget.projectId, page.id),
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
              VoidCallback onPreviewFor(ScanPage page, int index) => () =>
                  Navigator.of(context).push(
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
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.75,
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
                padding: const EdgeInsets.symmetric(vertical: 8),
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
          if (_importing)
            const ColoredBox(
              color: Color(0x66FFFFFF),
              child: Center(
                child: CircularProgressIndicator(
                  key: ValueKey('reviewImporting'),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => _viewModel.selectedIds.isEmpty
                ? Row(
                    children: [
                      Expanded(
                        child: _ReviewAddAction(
                          key: const ValueKey('reviewAddCamera'),
                          icon: Icons.photo_camera_outlined,
                          label: l10n.reviewAddCamera,
                          onPressed: _importing ? null : _openCamera,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ReviewAddAction(
                          key: const ValueKey('reviewAddGallery'),
                          icon: Icons.photo_library_outlined,
                          label: l10n.reviewAddGallery,
                          onPressed: _importing ? null : _importFromGallery,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ReviewAddAction(
                          key: const ValueKey('reviewAddFromFiles'),
                          icon: Icons.insert_drive_file_outlined,
                          label: l10n.homeImportFile,
                          onPressed: _importing ? null : _importFromFiles,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      IconButton(
                        key: const ValueKey('reviewSelectionCancel'),
                        onPressed: _viewModel.clearSelection,
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Text(
                          l10n.selectedCount(_viewModel.selectedIds.length),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('reviewSelectionRotate'),
                        onPressed: _viewModel.rotateSelected,
                        icon: const Icon(Icons.rotate_right),
                      ),
                      IconButton(
                        key: const ValueKey('reviewSelectionDuplicate'),
                        onPressed: _viewModel.duplicateSelected,
                        icon: const Icon(Icons.copy),
                      ),
                      IconButton(
                        key: const ValueKey('reviewSelectionDelete'),
                        onPressed: _viewModel.deleteSelected,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
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
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectionMode)
              Checkbox(value: selected, onChanged: (_) => onTap?.call()),
            SizedBox(
              width: 48,
              height: 64,
              child: RotatedBox(
                quarterTurns: page.rotationDegrees ~/ 90,
                child: hasThumb
                    ? Image.file(File(thumb), fit: BoxFit.cover)
                    : const ColoredBox(color: Colors.black12),
              ),
            ),
          ],
        ),
        title: Text(page.logicalPageLabel ?? '#${index + 1}'),
        subtitle: _buildWarnings(context),
        trailing: PopupMenuButton<String>(
          key: ValueKey('pageMenu-${page.id}'),
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
              PopupMenuItem(
                value: 'resplit',
                child: Text(l10n.spreadSplitAction),
              ),
            PopupMenuItem(value: 'label', child: Text(l10n.pageLabelAction)),
            PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
            PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
            PopupMenuItem(value: 'revert', child: Text(l10n.revertToOriginal)),
            PopupMenuItem(value: 'rescan', child: Text(l10n.rescan)),
            PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
          ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: selected
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RotatedBox(
              quarterTurns: page.rotationDegrees ~/ 90,
              child: hasThumb
                  ? Image.file(File(thumb), fit: BoxFit.cover)
                  : const ColoredBox(color: Colors.black12),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Text(
                page.logicalPageLabel ?? '#${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
            if (selectionMode)
              Positioned(
                left: 0,
                top: 0,
                child: Checkbox(value: selected, onChanged: (_) => onTap?.call()),
              ),
            Positioned(
              right: 0,
              top: 0,
              child: PopupMenuButton<String>(
                key: ValueKey('pageMenu-${page.id}'),
                icon: const Icon(Icons.more_vert, color: Colors.white),
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
                  PopupMenuItem(
                    value: 'adjust',
                    child: Text(l10n.adjustAction),
                  ),
                  PopupMenuItem(value: 'ocr', child: Text(l10n.ocrAction)),
                  if (page.spreadSiblingPageId != null)
                    PopupMenuItem(
                      value: 'resplit',
                      child: Text(l10n.spreadSplitAction),
                    ),
                  PopupMenuItem(
                    value: 'label',
                    child: Text(l10n.pageLabelAction),
                  ),
                  PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text(l10n.duplicate),
                  ),
                  PopupMenuItem(
                    value: 'revert',
                    child: Text(l10n.revertToOriginal),
                  ),
                  PopupMenuItem(value: 'rescan', child: Text(l10n.rescan)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
            ),
          ],
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
        page.processedImagePath ??
        page.thumbnailPath ??
        page.originalImagePath;
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
              ? Image.file(File(imagePath))
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
