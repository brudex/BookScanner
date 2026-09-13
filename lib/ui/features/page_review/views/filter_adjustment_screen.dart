import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/scan_page.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/use_cases/capture_page_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/filter_adjustment_view_model.dart';

/// Filter picker + brightness/contrast/sharpness adjustment screen (SPEC
/// 6.2). Reached from Page Review; applying re-runs the enhancement
/// pipeline for just this page, same as [CropCorrectionScreen] (SPEC 9.5).
class FilterAdjustmentScreen extends StatefulWidget {
  const FilterAdjustmentScreen({
    super.key,
    required this.projectId,
    required this.pageId,
    this.viewModel,
  });

  final String projectId;
  final String pageId;

  /// Injectable for widget tests; production code leaves this null.
  final FilterAdjustmentViewModel? viewModel;

  @override
  State<FilterAdjustmentScreen> createState() => _FilterAdjustmentScreenState();
}

class _FilterAdjustmentScreenState extends State<FilterAdjustmentScreen> {
  late final FilterAdjustmentViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        FilterAdjustmentViewModel(
          pageId: widget.pageId,
          pageRepository: locator<PageRepository>(),
          capturePageUseCase: locator<CapturePageUseCase>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final ok = await _viewModel.apply();
    if (!mounted) return;
    if (ok) {
      context.pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${_viewModel.error}')));
    }
  }

  String _filterLabel(AppLocalizations l10n, PageFilter filter) =>
      switch (filter) {
        PageFilter.original => l10n.filterOriginal,
        PageFilter.enhancedColor => l10n.filterEnhancedColor,
        PageFilter.grayscale => l10n.filterGrayscale,
        PageFilter.blackAndWhite => l10n.filterBlackAndWhite,
        PageFilter.photo => l10n.filterPhoto,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.adjustTitle),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_viewModel.error != null && _viewModel.page == null) {
            return Center(
              child: Text(
                '${_viewModel.error}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          final page = _viewModel.page!;
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: ColorFiltered(
                    key: const ValueKey('adjustPreview'),
                    // Live, GPU-side approximation of the chosen filter and
                    // brightness/contrast -- not pixel-identical to the real
                    // package:image pipeline that only runs once on Save
                    // (see _colorMatrixFor's doc comment). Sharpness has no
                    // cheap GPU equivalent, so it's not previewed live.
                    colorFilter: ColorFilter.matrix(
                      _colorMatrixFor(
                        _viewModel.filter,
                        _viewModel.brightness,
                        _viewModel.contrast,
                      ),
                    ),
                    child: Image.file(File(page.originalImagePath)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final filter in PageFilter.values)
                      ChoiceChip(
                        key: ValueKey('adjustFilterChip-${filter.name}'),
                        label: Text(_filterLabel(l10n, filter)),
                        selected: _viewModel.filter == filter,
                        onSelected: (_) => _viewModel.selectFilter(filter),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _AdjustSlider(
                      sliderKey: const ValueKey('adjustBrightnessSlider'),
                      label: l10n.brightnessLabel,
                      value: _viewModel.brightness,
                      min: -100,
                      max: 100,
                      onChanged: _viewModel.setBrightness,
                    ),
                    _AdjustSlider(
                      sliderKey: const ValueKey('adjustContrastSlider'),
                      label: l10n.contrastLabel,
                      value: _viewModel.contrast,
                      min: -100,
                      max: 100,
                      onChanged: _viewModel.setContrast,
                    ),
                    _AdjustSlider(
                      sliderKey: const ValueKey('adjustSharpnessSlider'),
                      label: l10n.sharpnessLabel,
                      value: _viewModel.sharpness,
                      min: 0,
                      max: 100,
                      onChanged: _viewModel.setSharpness,
                    ),
                  ],
                ),
              ),
            ],
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
                  key: const ValueKey('adjustCancelButton'),
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
                  key: const ValueKey('adjustApplyButton'),
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

class _AdjustSlider extends StatelessWidget {
  const _AdjustSlider({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        Expanded(
          child: Slider(
            key: sliderKey,
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Builds an approximate 4x5 [ColorFilter.matrix] (Android/Flutter's 0-255
/// per-channel convention) for live preview only. Brightness is modeled as
/// a multiplicative scale and contrast as a scale centered at 128 gray,
/// mirroring the *shape* of `DartImageEnhancementProvider`'s
/// `img.adjustColor(brightness: 1+b/100, contrast: 1+c/100)` call closely
/// enough for a real-time preview -- it is not the same code path and will
/// not produce pixel-identical output to what Save actually persists.
/// Grayscale/black-and-white use standard luminance weights; black-and-white
/// additionally applies a fixed steep contrast to visually approximate (not
/// replicate) the real pipeline's mean-luminance threshold, which has no
/// linear-matrix equivalent.
List<double> _colorMatrixFor(
  PageFilter filter,
  double brightness,
  double contrast,
) {
  final brightnessFactor = 1 + brightness / 100;
  final contrastFactor = 1 + contrast / 100;

  List<double> withScaleOffset(
    double rWeight,
    double gWeight,
    double bWeight,
    double extraContrast,
  ) {
    final effectiveContrast = contrastFactor * extraContrast;
    final scale = brightnessFactor * effectiveContrast;
    final offset = 128 * (1 - effectiveContrast);
    return [
      rWeight * scale,
      gWeight * scale,
      bWeight * scale,
      0,
      offset,
      rWeight * scale,
      gWeight * scale,
      bWeight * scale,
      0,
      offset,
      rWeight * scale,
      gWeight * scale,
      bWeight * scale,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  return switch (filter) {
    PageFilter.original => [
      brightnessFactor * contrastFactor,
      0,
      0,
      0,
      128 * (1 - contrastFactor),
      0,
      brightnessFactor * contrastFactor,
      0,
      0,
      128 * (1 - contrastFactor),
      0,
      0,
      brightnessFactor * contrastFactor,
      0,
      128 * (1 - contrastFactor),
      0,
      0,
      0,
      1,
      0,
    ],
    PageFilter.enhancedColor => [
      brightnessFactor * contrastFactor * 1.1,
      0,
      0,
      0,
      128 * (1 - contrastFactor),
      0,
      brightnessFactor * contrastFactor * 1.1,
      0,
      0,
      128 * (1 - contrastFactor),
      0,
      0,
      brightnessFactor * contrastFactor * 1.1,
      0,
      128 * (1 - contrastFactor),
      0,
      0,
      0,
      1,
      0,
    ],
    PageFilter.photo => [
      brightnessFactor * contrastFactor * 1.05,
      0,
      0,
      0,
      128 * (1 - contrastFactor) + 4,
      0,
      brightnessFactor * contrastFactor * 1.05,
      0,
      0,
      128 * (1 - contrastFactor) + 2,
      0,
      0,
      brightnessFactor * contrastFactor * 1.05,
      0,
      128 * (1 - contrastFactor),
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
