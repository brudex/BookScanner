import 'dart:io';

import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/page_review/view_models/filter_adjustment_view_model.dart';
import 'package:bookscanner/ui/features/page_review/views/filter_adjustment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _FakePageRepository implements PageRepository {
  final _pages = <String, ScanPage>{};

  @override
  Future<ScanPage?> getPage(String pageId) async => _pages[pageId];

  @override
  Future<void> updatePage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<void> addPage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      _pages.values.toList();

  @override
  Future<void> deletePage(String pageId) async {}

  @override
  Future<void> duplicatePage(String pageId) async {}

  @override
  Future<void> reorderPages(
    String projectId,
    List<String> newPageIdOrder,
  ) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

class _FakeDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<Quad?> detectQuad(String imagePath) async => null;
}

/// The widget tests below don't exercise `apply()`, so `enhance()` is never
/// actually invoked — this only needs to satisfy `CapturePageUseCase`'s
/// constructor, mirroring crop_correction_screen_test.dart's convention.
class _NoopEnhancementProvider implements ImageEnhancementProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1');

  @override
  Future<double> scoreQuality(String imagePath) async => 0.9;

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async =>
      EnhancementResult(
        processedImagePath: request.outputImagePath,
        thumbnailPath: request.outputImagePath,
        qualityScore: 0.9,
        providerInfo: info,
      );
}

class _FakePaths implements PagePathAllocator {
  @override
  String originalPathFor(String pageId, {required String ext}) =>
      '/tmp/$pageId-original.$ext';

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      '/tmp/$pageId-processed.$ext';

  @override
  String thumbnailPathFor(String pageId) => '/tmp/$pageId-thumb.jpg';

  @override
  String exportPathFor(String jobId, String extension) =>
      '/tmp/$jobId.$extension';
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  late Directory tmpDir;
  late _FakePageRepository pageRepository;
  late FilterAdjustmentViewModel viewModel;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp(
      'filter_adjustment_screen_test_',
    );
    final image = img.Image(width: 200, height: 100);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    final imagePath = p.join(tmpDir.path, 'page.jpg');
    await File(imagePath).writeAsBytes(img.encodeJpg(image));

    pageRepository = _FakePageRepository();
    await pageRepository.addPage(
      ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: imagePath,
        status: PageStatus.ready,
      ),
    );

    viewModel = FilterAdjustmentViewModel(
      pageId: 'p1',
      pageRepository: pageRepository,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pageRepository,
        enhancementProvider: _NoopEnhancementProvider(),
        detectionProvider: _FakeDetectionProvider(),
        fileStorage: _FakePaths(),
      ),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  testWidgets(
    'shows a filter chip per PageFilter value and the three sliders',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          FilterAdjustmentScreen(
            projectId: 'proj1',
            pageId: 'p1',
            viewModel: viewModel,
          ),
        ),
      );
      await tester.pump();

      for (final filter in PageFilter.values) {
        expect(
          find.byKey(ValueKey('adjustFilterChip-${filter.name}')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('adjustBrightnessSlider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adjustContrastSlider')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('adjustSharpnessSlider')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('adjustApplyButton')), findsOneWidget);
      expect(find.byKey(const ValueKey('adjustCancelButton')), findsOneWidget);
    },
  );

  testWidgets('tapping a filter chip selects it', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FilterAdjustmentScreen(
          projectId: 'proj1',
          pageId: 'p1',
          viewModel: viewModel,
        ),
      ),
    );
    await tester.pump();

    expect(viewModel.filter, PageFilter.original);

    await tester.tap(find.byKey(const ValueKey('adjustFilterChip-grayscale')));
    await tester.pump();

    expect(viewModel.filter, PageFilter.grayscale);
  });

  testWidgets('dragging the brightness slider updates the view model', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        FilterAdjustmentScreen(
          projectId: 'proj1',
          pageId: 'p1',
          viewModel: viewModel,
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('adjustBrightnessSlider')),
      const Offset(50, 0),
    );
    await tester.pump();

    expect(viewModel.brightness, greaterThan(0));
  });
}
