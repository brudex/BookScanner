import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/detect_page_anomalies_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
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

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        PageReviewViewModel(
          projectId: widget.projectId,
          pageRepository: locator<PageRepository>(),
          detectAnomaliesUseCase: locator<DetectPageAnomaliesUseCase>(),
        );
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
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
          IconButton(
            key: const ValueKey('reviewAddPageButton'),
            icon: const Icon(Icons.add_a_photo_outlined),
            tooltip: l10n.newScan,
            onPressed: () =>
                context.push(AppRoutes.captureFor(widget.projectId)),
          ),
        ],
      ),
      body: ListenableBuilder(
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
                  onRotate: () => _viewModel.rotate(page),
                  onDuplicate: () => _viewModel.duplicate(page),
                  onDelete: () => _viewModel.delete(page),
                  onRescan: onRescanFor(page),
                  onCrop: onCropFor(page),
                  onAdjust: onAdjustFor(page),
                  onOcr: onOcrFor(page),
                  onResplit: onResplitFor(page),
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
                onRotate: () => _viewModel.rotate(page),
                onDuplicate: () => _viewModel.duplicate(page),
                onDelete: () => _viewModel.delete(page),
                onRescan: onRescanFor(page),
                onCrop: onCropFor(page),
                onAdjust: onAdjustFor(page),
                onOcr: onOcrFor(page),
                onResplit: onResplitFor(page),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) => FilledButton(
              key: const ValueKey('reviewExportButton'),
              onPressed: _viewModel.pages.isEmpty
                  ? null
                  : () => context.push(AppRoutes.exportFor(widget.projectId)),
              child: Text(l10n.exportTitle),
            ),
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
    required this.onRescan,
    required this.onCrop,
    required this.onAdjust,
    required this.onOcr,
    required this.onResplit,
  });

  final ScanPage page;
  final int index;
  final AppLocalizations l10n;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onRescan;
  final VoidCallback onCrop;
  final VoidCallback onAdjust;
  final VoidCallback onOcr;
  final VoidCallback onResplit;

  @override
  Widget build(BuildContext context) {
    final thumb =
        page.thumbnailPath ?? page.processedImagePath ?? page.originalImagePath;
    final hasThumb = File(thumb).existsSync();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onCrop,
        leading: SizedBox(
          width: 48,
          height: 64,
          child: RotatedBox(
            quarterTurns: page.rotationDegrees ~/ 90,
            child: hasThumb
                ? Image.file(File(thumb), fit: BoxFit.cover)
                : const ColoredBox(color: Colors.black12),
          ),
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
              case 'rotate':
                onRotate();
              case 'duplicate':
                onDuplicate();
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
            PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
            PopupMenuItem(value: 'duplicate', child: Text(l10n.duplicate)),
            PopupMenuItem(value: 'rescan', child: Text(l10n.rescan)),
            PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
          ],
        ),
      ),
    );
  }

  Widget? _buildWarnings(BuildContext context) {
    final labels = <String>[];
    if (page.duplicateOfPageId != null &&
        !page.dismissedWarnings.contains('duplicate')) {
      labels.add(l10n.possibleDuplicate);
    }
    if (page.likelyMissingBefore &&
        !page.dismissedWarnings.contains('missing')) {
      labels.add(l10n.possibleMissingPage);
    }
    if (page.status == PageStatus.needsRescan) {
      labels.add(l10n.lowQuality);
    }
    if (labels.isEmpty) return null;
    return Text(
      labels.join(' · '),
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 12,
      ),
    );
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
    required this.onRescan,
    required this.onCrop,
    required this.onAdjust,
    required this.onOcr,
    required this.onResplit,
  });

  final ScanPage page;
  final int index;
  final AppLocalizations l10n;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onRescan;
  final VoidCallback onCrop;
  final VoidCallback onAdjust;
  final VoidCallback onOcr;
  final VoidCallback onResplit;

  @override
  Widget build(BuildContext context) {
    final thumb =
        page.thumbnailPath ?? page.processedImagePath ?? page.originalImagePath;
    final hasThumb = File(thumb).existsSync();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCrop,
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
                    case 'rotate':
                      onRotate();
                    case 'duplicate':
                      onDuplicate();
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
                  PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text(l10n.duplicate),
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
