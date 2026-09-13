import 'package:flutter/material.dart';

import '../../../../domain/models/ocr_block.dart';
import '../../../../domain/repositories/ocr_repository.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/run_ocr_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/ocr_review_view_model.dart';

/// OCR text review/correction UI (SPEC 6.4, 5.3). Shows an honest "not yet
/// run" state until the user explicitly triggers recognition, then renders
/// recognized blocks in reading order with low-confidence spans flagged and
/// tap-to-correct editing.
class OcrReviewScreen extends StatefulWidget {
  const OcrReviewScreen({
    super.key,
    required this.projectId,
    required this.pageId,
    this.viewModel,
  });

  final String projectId;
  final String pageId;

  /// Injectable for widget tests; production code leaves this null.
  final OcrReviewViewModel? viewModel;

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  late final OcrReviewViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        OcrReviewViewModel(
          pageId: widget.pageId,
          pageRepository: locator<PageRepository>(),
          ocrRepository: locator<OcrRepository>(),
          runOcrUseCase: locator<RunOcrUseCase>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _editBlock(OcrBlock block) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: block.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ocrEditBlockTitle),
        content: TextField(
          key: const ValueKey('ocrEditBlockField'),
          controller: controller,
          maxLines: null,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('ocrEditBlockSaveButton'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (newText != null && newText != block.text) {
      await _viewModel.correctBlock(block.id, newText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ocrReviewTitle),
        actions: [
          ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              if (!_viewModel.hasRun || _viewModel.running) {
                return const SizedBox.shrink();
              }
              return IconButton(
                key: const ValueKey('ocrRerunButton'),
                icon: const Icon(Icons.refresh),
                tooltip: l10n.ocrRerunButton,
                onPressed: () => _viewModel.runOcr(force: true),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading) {
            return const Center(
              child: CircularProgressIndicator(
                key: ValueKey('ocrLoadingIndicator'),
              ),
            );
          }
          if (_viewModel.error != null && _viewModel.page == null) {
            return Center(child: Text('${_viewModel.error}'));
          }
          if (_viewModel.running) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.ocrRunningLabel),
                ],
              ),
            );
          }
          if (!_viewModel.hasRun) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.text_snippet_outlined,
                      size: 56,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.ocrEmptyTitle,
                      key: const ValueKey('ocrReviewEmptyState'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (_viewModel.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          '${_viewModel.error}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    FilledButton(
                      key: const ValueKey('ocrRunButton'),
                      onPressed: _viewModel.runOcr,
                      child: Text(l10n.ocrRunButton),
                    ),
                  ],
                ),
              ),
            );
          }
          if (_viewModel.blocks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.text_snippet_outlined,
                      size: 56,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.ocrNoTextFound,
                      key: const ValueKey('ocrNoTextFoundState'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            key: const ValueKey('ocrBlockList'),
            padding: const EdgeInsets.all(16),
            itemCount: _viewModel.blocks.length,
            itemBuilder: (context, index) {
              final block = _viewModel.blocks[index];
              return _BlockTile(
                key: ValueKey('ocrBlock-${block.id}'),
                block: block,
                onTap: () => _editBlock(block),
              );
            },
          );
        },
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({super.key, required this.block, required this.onTap});

  final OcrBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = switch (block.blockType) {
      BlockType.heading => Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      BlockType.pageNumber ||
      BlockType.header ||
      BlockType.footer => Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
      BlockType.quotation => Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
      _ => Theme.of(context).textTheme.bodyLarge,
    };
    final prefix = block.blockType == BlockType.listItem ? '• ' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: block.isLowConfidence
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
          : null,
      child: ListTile(
        onTap: onTap,
        title: Text('$prefix${block.text}', style: style),
        subtitle: block.isLowConfidence || block.wasCorrected
            ? Text(
                block.wasCorrected
                    ? l10n.ocrCorrectedLabel
                    : l10n.ocrLowConfidenceLabel,
                style: TextStyle(
                  color: block.wasCorrected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              )
            : null,
      ),
    );
  }
}
