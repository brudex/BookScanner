import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/filter_adjustment_view_model.dart';
import '../view_models/post_capture_edit_view_model.dart';
import 'crop_correction_screen.dart';
import '../../../core/widgets/page_image.dart';
import 'preview_progress_overlay.dart';

/// Filter / look polish after crop (Tap Scanner order: capture → crop →
/// filters → name). Crop is not offered here — it already ran.
class PostCaptureEditScreen extends StatefulWidget {
  const PostCaptureEditScreen({
    super.key,
    required this.projectId,
    this.initialPageId,
    this.viewModel,
  });

  final String projectId;

  /// Page to open when arriving from crop Next.
  final String? initialPageId;

  final PostCaptureEditViewModel? viewModel;

  @override
  State<PostCaptureEditScreen> createState() => _PostCaptureEditScreenState();
}

class _PostCaptureEditScreenState extends State<PostCaptureEditScreen> {
  late final PostCaptureEditViewModel _viewModel;
  bool _leavingForward = false;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        PostCaptureEditViewModel(
          projectId: widget.projectId,
          pageRepository: locator<PageRepository>(),
          projectRepository: locator<ProjectRepository>(),
          capturePageUseCase: locator<CapturePageUseCase>(),
        );
    _viewModel.initialize(initialPageId: widget.initialPageId);
  }

  @override
  void dispose() {
    _viewModel.editor?.cancelPendingPreview();
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _backToCrop() async {
    final page = _viewModel.currentPage;
    if (page == null) {
      context.pop();
      return;
    }
    _leavingForward = true;
    context.pushReplacement(
      AppRoutes.cropCorrectionFor(widget.projectId, page.id),
      extra: CropFlowMode.postCapture,
    );
  }

  Future<void> _finish() async {
    _leavingForward = true;
    final l10n = AppLocalizations.of(context);
    final name = await _promptScanName(context, l10n);
    if (!mounted) return;
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await _viewModel.renameProject(trimmed);
    }
    if (!mounted) return;
    context.pushReplacement(AppRoutes.pageReviewFor(widget.projectId));
  }

  Future<void> _onSave() async {
    // apply() marks saving synchronously; ignore a second tap mid-save.
    if (_viewModel.editor?.saving ?? false) return;
    _leavingForward = true;
    final ok = await _viewModel.saveAndAdvance();
    if (!mounted) return;
    if (!ok) {
      _leavingForward = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).saveChangesFailed)),
      );
      return;
    }
    if (_viewModel.finished) {
      await _finish();
      return;
    }
    final next = _viewModel.currentPage;
    if (next == null) return;
    context.pushReplacement(
      AppRoutes.cropCorrectionFor(widget.projectId, next.id),
      extra: CropFlowMode.postCapture,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _leavingForward) return;
        await _backToCrop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            key: const ValueKey('postCaptureBackButton'),
            icon: const Icon(Icons.arrow_back),
            onPressed: _backToCrop,
          ),
          title: ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              final total = _viewModel.pages.length;
              final n = total == 0 ? 0 : _viewModel.index + 1;
              return Text('${l10n.adjustTitle}  ·  $n/$total');
            },
          ),
        ),
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_viewModel.pages.isEmpty || _viewModel.finished) {
              return const Center(child: CircularProgressIndicator());
            }
            final editor = _viewModel.editor;
            if (editor == null || editor.loading || editor.page == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListenableBuilder(
              listenable: editor,
              builder: (context, _) => _EditorBody(editor: editor, l10n: l10n),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            // Outer: page list / current editor. Inner: that editor's own
            // saving flag -- listening only to the page list left the button
            // tappable with no spinner while a save ran.
            child: ListenableBuilder(
              listenable: _viewModel,
              builder: (context, _) => ListenableBuilder(
                listenable: _viewModel.editor ?? _viewModel,
                builder: (context, _) {
                  final editor = _viewModel.editor;
                  final saving = editor?.saving ?? false;
                  final label = _viewModel.isLastPage
                      ? l10n.postCaptureSave
                      : l10n.postCaptureNext;
                  return SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey('postCaptureSaveButton'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: saving ? null : _onSave,
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(LucideIcons.chevronRight, size: 20),
                              ],
                            ),
                    ),
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

class _EditorBody extends StatelessWidget {
  const _EditorBody({required this.editor, required this.l10n});

  final FilterAdjustmentViewModel editor;
  final AppLocalizations l10n;

  String _filterLabel(PageFilter filter) => switch (filter) {
    PageFilter.original => l10n.filterOriginal,
    PageFilter.enhancedColor => l10n.filterEnhancedColor,
    PageFilter.grayscale => l10n.filterGrayscale,
    PageFilter.blackAndWhite => l10n.filterBlackAndWhite,
    PageFilter.photo => l10n.filterPhoto,
  };

  @override
  Widget build(BuildContext context) {
    final previewPath = editor.previewImagePath!;
    final preview = PageImage(
      path: previewPath,
      key: ValueKey('postCapturePreview-$previewPath-${editor.previewEpoch}'),
      fit: BoxFit.contain,
    );
    return Column(
      children: [
        Expanded(
          child: Padding(
            // Inset like Tap filter screen — room around the page preview.
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: PreviewProgressOverlay(
              busy: editor.previewRendering,
              saving: editor.saving,
              child: Center(
                child: editor.showingSavedProcessed
                    ? preview
                    : ColorFiltered(
                        colorFilter: ColorFilter.matrix(
                          _previewMatrix(
                            editor.filter,
                            editor.brightness,
                            editor.contrast,
                          ),
                        ),
                        child: preview,
                      ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final filter in PageFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('postCaptureFilter-${filter.name}'),
                    label: Text(_filterLabel(filter)),
                    selected: editor.filter == filter,
                    // Locked while a look is applied so taps don't pile up.
                    onSelected: editor.previewRendering || editor.saving
                        ? null
                        : (_) => editor.selectFilter(filter),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            children: [
              _SliderRow(
                enabled: !editor.saving,
                label: l10n.brightnessLabel,
                value: editor.brightness,
                min: -100,
                max: 100,
                onChanged: editor.setBrightness,
              ),
              _SliderRow(
                enabled: !editor.saving,
                label: l10n.contrastLabel,
                value: editor.contrast,
                min: -100,
                max: 100,
                onChanged: editor.setContrast,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    this.enabled = true,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// False while saving, so the look cannot change mid-save.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    );
  }
}

Future<String?> _promptScanName(BuildContext context, AppLocalizations l10n) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NameScanDialog(l10n: l10n),
    );

class _NameScanDialog extends StatefulWidget {
  const _NameScanDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_NameScanDialog> createState() => _NameScanDialogState();
}

class _NameScanDialogState extends State<_NameScanDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: DateFormat('MM-dd HH:mm').format(DateTime.now()),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.nameScanTitle),
      content: TextField(
        key: const ValueKey('captureNameField'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.l10n.nameScanLabel),
      ),
      actions: [
        TextButton(
          key: const ValueKey('captureNameCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('captureNameSaveButton'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.l10n.save),
        ),
      ],
    );
  }
}

/// Same matrix family as [FilterAdjustmentScreen]'s live preview.
List<double> _previewMatrix(
  PageFilter filter,
  double brightness,
  double contrast,
) {
  final b = brightness.clamp(-100, 100) / 100;
  final c = 1.0 + (contrast.clamp(-100, 100) / 100);
  final t = (1.0 - c) / 2.0 + b;
  List<double> withScaleOffset(double r, double g, double bl, double scale) => [
    r * c * scale,
    g * c * scale,
    bl * c * scale,
    0,
    t * 255,
    r * c * scale,
    g * c * scale,
    bl * c * scale,
    0,
    t * 255,
    r * c * scale,
    g * c * scale,
    bl * c * scale,
    0,
    t * 255,
    0,
    0,
    0,
    1,
    0,
  ];
  return switch (filter) {
    PageFilter.original => [
      c,
      0,
      0,
      0,
      t * 255,
      0,
      c,
      0,
      0,
      t * 255,
      0,
      0,
      c,
      0,
      t * 255,
      0,
      0,
      0,
      1,
      0,
    ],
    PageFilter.enhancedColor => [
      c * 1.12,
      0,
      0,
      0,
      (t + 0.02) * 255,
      0,
      c * 1.12,
      0,
      0,
      (t + 0.02) * 255,
      0,
      0,
      c * 1.18,
      0,
      (t + 0.02) * 255,
      0,
      0,
      0,
      1,
      0,
    ],
    PageFilter.photo => [
      c * 1.05,
      0,
      0,
      0,
      (t + 0.02) * 255,
      0,
      c * 1.05,
      0,
      0,
      (t + 0.02) * 255,
      0,
      0,
      c * 1.05,
      0,
      (t + 0.02) * 255,
      0,
      0,
      0,
      1,
      0,
    ],
    PageFilter.grayscale => withScaleOffset(0.2126, 0.7152, 0.0722, 1),
    PageFilter.blackAndWhite => withScaleOffset(0.2126, 0.7152, 0.0722, 6),
  };
}
