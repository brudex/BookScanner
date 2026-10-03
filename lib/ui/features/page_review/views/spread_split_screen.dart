import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/services/local/app_paths.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/process_book_spread_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/spread_split_view_model.dart';
import '../../../core/widgets/page_image.dart';

/// Manual book-spread split correction screen (SPEC 5.2 acceptance
/// criterion: "the app creates two ordered pages and lets the user correct
/// the split"). Reached from Page Review's popup menu for either half of a
/// split spread; applying re-runs the split/detect/enhance/dewarp pipeline
/// for both sibling pages in place.
class SpreadSplitScreen extends StatefulWidget {
  const SpreadSplitScreen({
    super.key,
    required this.projectId,
    required this.pageId,
    this.viewModel,
  });

  final String projectId;
  final String pageId;

  /// Injectable for widget tests; production code leaves this null.
  final SpreadSplitViewModel? viewModel;

  @override
  State<SpreadSplitScreen> createState() => _SpreadSplitScreenState();
}

class _SpreadSplitScreenState extends State<SpreadSplitScreen> {
  late final SpreadSplitViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        SpreadSplitViewModel(
          pageId: widget.pageId,
          pageRepository: locator<PageRepository>(),
          projectRepository: locator<ProjectRepository>(),
          processBookSpreadUseCase: locator<ProcessBookSpreadUseCase>(),
          paths: locator<AppPaths>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    // apply() marks saving synchronously; ignore a second tap mid-save.
    if (_viewModel.saving) return;
    final ok = await _viewModel.apply();
    if (!mounted) return;
    if (ok) {
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).saveChangesFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.spreadSplitTitle),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewModel.error != null && _viewModel.spreadImagePath == null) {
            return Center(
              child: Text(
                '${_viewModel.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          final imageSize = _viewModel.imageSize;
          final imagePath = _viewModel.spreadImagePath;
          if (imageSize == null || imagePath == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final available = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final fitted = applyBoxFit(BoxFit.contain, imageSize, available);
              final destSize = fitted.destination;
              final originX = (available.width - destSize.width) / 2;
              final originY = (available.height - destSize.height) / 2;
              final lineX = originX + _viewModel.gutterX * destSize.width;

              return Stack(
                children: [
                  Positioned(
                    left: originX,
                    top: originY,
                    width: destSize.width,
                    height: destSize.height,
                    child: PageImage(path: imagePath, fit: BoxFit.fill),
                  ),
                  Positioned(
                    left: lineX - 1,
                    top: originY,
                    width: 2,
                    height: destSize.height,
                    child: IgnorePointer(
                      child: Container(color: Colors.blueAccent),
                    ),
                  ),
                  Positioned(
                    left: lineX - 22,
                    top: originY + destSize.height / 2 - 22,
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      key: const ValueKey('spreadSplitHandle'),
                      onPanUpdate: (details) => _viewModel.dragGutter(
                        details.delta.dx / destSize.width,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                            color: Colors.blueAccent,
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                        margin: const EdgeInsets.all(10),
                        child: const Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('spreadSplitCancelButton'),
                  onPressed: () => context.pop(),
                  child: Text(
                    l10n.cancel,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('spreadSplitApplyButton'),
                  onPressed: _viewModel.saving ? null : _apply,
                  child: _viewModel.saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
