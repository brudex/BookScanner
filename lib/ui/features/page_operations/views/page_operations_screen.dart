import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/providers/document_export_provider.dart';
import '../../../../domain/providers/pdf_rasterizer_provider.dart';
import '../../../../domain/repositories/working_session_path_allocator.dart';
import '../../../../domain/use_cases/export_page_inputs_use_case.dart';
import '../../../../domain/use_cases/load_page_source_use_case.dart';
import '../../../../domain/use_cases/load_project_page_inputs_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../../export/views/export_job_status_views.dart';
import '../view_models/page_operations_view_model.dart';
import 'source_picker_sheet.dart';

/// Multi-source page-composition screen (SPEC 6.5 "editing"): merges pages
/// from other projects, imported PDFs, or images into one working document,
/// then reorders/rotates/duplicates/deletes/inserts/replaces/splits/
/// extracts before exporting as PDF. Entered from [ExportScreen]'s compose
/// action.
class PageOperationsScreen extends StatefulWidget {
  const PageOperationsScreen({
    super.key,
    required this.projectId,
    this.viewModel,
  });

  final String projectId;

  /// Injectable for widget tests; production code leaves this null.
  final PageOperationsViewModel? viewModel;

  @override
  State<PageOperationsScreen> createState() => _PageOperationsScreenState();
}

class _PageOperationsScreenState extends State<PageOperationsScreen> {
  late final PageOperationsViewModel _viewModel;
  bool _extractMode = false;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        PageOperationsViewModel(
          hostProjectId: widget.projectId,
          projectPageLoader: locator<LoadProjectPageInputsUseCase>(),
          pageSourceLoader: locator<LoadPageSourceUseCase>(),
          exportUseCase: locator<ExportPageInputsUseCase>(),
          workingPaths: locator<WorkingSessionPathAllocator>(),
          rasterizer: locator<PdfRasterizerProvider>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleAddPages() async {
    final source = await showSourcePickerSheet(
      context: context,
      viewModel: _viewModel,
    );
    if (source != null) await _viewModel.mergeAppend(source);
  }

  Future<void> _handleInsertBefore(String pageId) async {
    final source = await showSourcePickerSheet(
      context: context,
      viewModel: _viewModel,
    );
    if (source != null) await _viewModel.insertBefore(pageId, source);
  }

  Future<void> _handleReplace(String pageId) async {
    final source = await showSourcePickerSheet(
      context: context,
      viewModel: _viewModel,
    );
    if (source != null) await _viewModel.replace(pageId, source);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.composeTitle),
        actions: [
          IconButton(
            key: const ValueKey('composeAddPagesButton'),
            icon: const Icon(Icons.add_outlined),
            tooltip: l10n.composeAddPagesAction,
            onPressed: _handleAddPages,
          ),
          IconButton(
            key: const ValueKey('composeSelectForExtractButton'),
            icon: Icon(_extractMode ? Icons.close : Icons.checklist_outlined),
            tooltip: l10n.composeSelectForExtractAction,
            onPressed: () => setState(() => _extractMode = !_extractMode),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final job = _viewModel.job;
          if (job != null) {
            if (job.status == ExportJobStatus.completed) {
              return ExportCompletedView(job: job, l10n: l10n);
            }
            return ExportFailedView(
              job: job,
              l10n: l10n,
              onRetry: _viewModel.resetExportState,
            );
          }
          final splitJobs = _viewModel.splitJobs;
          if (splitJobs != null) {
            return _SplitResultsView(jobs: splitJobs, l10n: l10n);
          }
          if (_viewModel.progress != null) {
            return _ExportingView(
              progress: _viewModel.progress!,
              jobsCompleted: _viewModel.jobsCompleted,
              jobsTotal: _viewModel.jobsTotal,
              l10n: l10n,
            );
          }
          return _buildComposer(context, l10n);
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading ||
              _viewModel.progress != null ||
              _viewModel.job != null ||
              _viewModel.splitJobs != null) {
            return const SizedBox.shrink();
          }
          return _buildBottomBar(l10n);
        },
      ),
    );
  }

  Widget _buildComposer(BuildContext context, AppLocalizations l10n) {
    final pages = _viewModel.pages;
    if (pages.isEmpty) {
      return Center(child: Text(l10n.libraryEmptyTitle));
    }
    final missingOcrCount = pages.where((p) => p.ocrBlocks.isEmpty).length;
    return Column(
      children: [
        if (missingOcrCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.composePagesMissingOcrWarning(missingOcrCount, pages.length),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            key: const ValueKey('pageOperationsList'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: pages.length,
            onReorder: _viewModel.reorder,
            itemBuilder: (context, index) {
              final page = pages[index];
              final isMarkedSplitAfter = _viewModel.splitAfterPageIds.contains(
                page.pageId,
              );
              return Column(
                key: ValueKey('page-${page.pageId}'),
                children: [
                  _ComposedPageTile(
                    page: page,
                    index: index,
                    l10n: l10n,
                    extractMode: _extractMode,
                    isSelectedForExtract: _viewModel.selectedForExtract
                        .contains(page.pageId),
                    isMarkedSplitAfter: isMarkedSplitAfter,
                    onToggleSelected: () =>
                        _viewModel.toggleSelectedForExtract(page.pageId),
                    onRotate: () => _viewModel.rotate(page.pageId),
                    onDuplicate: () => _viewModel.duplicate(page.pageId),
                    onDelete: () => _viewModel.delete(page.pageId),
                    onInsertBefore: () => _handleInsertBefore(page.pageId),
                    onReplace: () => _handleReplace(page.pageId),
                    onToggleSplitAfter: () =>
                        _viewModel.toggleSplitAfter(page.pageId),
                  ),
                  if (isMarkedSplitAfter)
                    const Divider(thickness: 2, indent: 32, endIndent: 32),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    if (_extractMode) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const ValueKey('composeExtractButton'),
            onPressed: _viewModel.selectedForExtract.isEmpty
                ? null
                : () => _viewModel.extractSelected(
                    title: l10n.composeExtractAction,
                  ),
            child: Text(l10n.composeExtractAction),
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          key: const ValueKey('composeExportButton'),
          onPressed: _viewModel.pages.isEmpty
              ? null
              : () => _viewModel.splitAfterPageIds.isEmpty
                    ? _viewModel.exportWhole(title: l10n.composeTitle)
                    : _viewModel.exportSplit(titlePrefix: l10n.composeTitle),
          child: Text(l10n.composeExportAction),
        ),
      ),
    );
  }
}

class _ComposedPageTile extends StatelessWidget {
  const _ComposedPageTile({
    required this.page,
    required this.index,
    required this.l10n,
    required this.extractMode,
    required this.isSelectedForExtract,
    required this.isMarkedSplitAfter,
    required this.onToggleSelected,
    required this.onRotate,
    required this.onDuplicate,
    required this.onDelete,
    required this.onInsertBefore,
    required this.onReplace,
    required this.onToggleSplitAfter,
  });

  final ExportPageInput page;
  final int index;
  final AppLocalizations l10n;
  final bool extractMode;
  final bool isSelectedForExtract;
  final bool isMarkedSplitAfter;
  final VoidCallback onToggleSelected;
  final VoidCallback onRotate;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onInsertBefore;
  final VoidCallback onReplace;
  final VoidCallback onToggleSplitAfter;

  @override
  Widget build(BuildContext context) {
    final hasThumb = File(page.imagePath).existsSync();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: extractMode
            ? Checkbox(
                key: ValueKey('composeSelectCheckbox-${page.pageId}'),
                value: isSelectedForExtract,
                onChanged: (_) => onToggleSelected(),
              )
            : SizedBox(
                width: 48,
                height: 64,
                child: RotatedBox(
                  quarterTurns: page.rotationDegrees ~/ 90,
                  child: hasThumb
                      ? Image.file(File(page.imagePath), fit: BoxFit.cover)
                      : const ColoredBox(color: Colors.black12),
                ),
              ),
        title: Text(page.logicalPageLabel ?? '#${index + 1}'),
        subtitle: isMarkedSplitAfter
            ? Text(l10n.composeSplitAfterAction)
            : null,
        trailing: extractMode
            ? null
            : PopupMenuButton<String>(
                key: ValueKey('composeMenu-${page.pageId}'),
                onSelected: (action) {
                  switch (action) {
                    case 'rotate':
                      onRotate();
                    case 'duplicate':
                      onDuplicate();
                    case 'insertBefore':
                      onInsertBefore();
                    case 'replace':
                      onReplace();
                    case 'splitAfter':
                      onToggleSplitAfter();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rotate', child: Text(l10n.rotate)),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text(l10n.duplicate),
                  ),
                  PopupMenuItem(
                    value: 'insertBefore',
                    child: Text(l10n.composeInsertBeforeAction),
                  ),
                  PopupMenuItem(
                    value: 'replace',
                    child: Text(l10n.composeReplaceAction),
                  ),
                  PopupMenuItem(
                    value: 'splitAfter',
                    child: Text(
                      isMarkedSplitAfter
                          ? l10n.composeRemoveSplitAfterAction
                          : l10n.composeSplitAfterAction,
                    ),
                  ),
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
      ),
    );
  }
}

class _ExportingView extends StatelessWidget {
  const _ExportingView({
    required this.progress,
    required this.jobsCompleted,
    required this.jobsTotal,
    required this.l10n,
  });

  final double progress;
  final int jobsCompleted;
  final int jobsTotal;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            key: const ValueKey('composeExportProgressBar'),
          ),
          const SizedBox(height: 16),
          Text(
            jobsTotal > 1
                ? l10n.composeExportingJobOfTotal(jobsCompleted + 1, jobsTotal)
                : l10n.exportInProgress,
          ),
        ],
      ),
    ),
  );
}

class _SplitResultsView extends StatelessWidget {
  const _SplitResultsView({required this.jobs, required this.l10n});

  final List<ExportJob> jobs;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('composeSplitResultsList'),
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        l10n.composeSplitResultsTitle(jobs.length),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 16),
      for (final job in jobs)
        Card(
          key: ValueKey('splitResultJob-${job.id}'),
          child: ListTile(
            leading: Icon(
              job.status == ExportJobStatus.completed
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: job.status == ExportJobStatus.completed
                  ? Colors.green
                  : Colors.red,
            ),
            title: Text(
              job.status == ExportJobStatus.completed
                  ? l10n.exportComplete
                  : l10n.exportFailed,
            ),
            trailing: job.status == ExportJobStatus.completed
                ? IconButton(
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () {
                      final path = job.outputPath;
                      if (path != null) {
                        SharePlus.instance.share(
                          ShareParams(files: [XFile(path)]),
                        );
                      }
                    },
                  )
                : null,
          ),
        ),
    ],
  );
}
