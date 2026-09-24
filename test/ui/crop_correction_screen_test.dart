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
import 'package:bookscanner/ui/features/page_review/view_models/crop_correction_view_model.dart';
import 'package:bookscanner/ui/features/page_review/views/crop_correction_screen.dart';
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
  late CropCorrectionViewModel viewModel;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('crop_screen_test_');
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

    viewModel = CropCorrectionViewModel(
      pageId: 'p1',
      pageRepository: pageRepository,
      capturePageUseCase: CapturePageUseCase(
        pageRepository: pageRepository,
        enhancementProvider: _NoopEnhancementProvider(),
        detectionProvider: _FakeDetectionProvider(),
        fileStorage: _FakePaths(),
      ),
      detectionProvider: _FakeDetectionProvider(),
    );
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  testWidgets('shows loading then the image with eight crop handles', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CropCorrectionScreen(
          projectId: 'proj1',
          pageId: 'p1',
          viewModel: viewModel,
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // `initState` already fired an `initialize()` call, but that call's
    // `dart:ui.instantiateImageCodec` await started in the fake-async test
    // zone and never resolves there — a well-known `flutter_test` limit on
    // real image decoding, not a product bug. Re-running `initialize()`
    // fully inside `runAsync` (idempotent: it just reloads the same page)
    // gives the codec a real event loop to complete on.
    await tester.runAsync(() => viewModel.initialize());
    await tester.pump();

    for (final handle in CropHandle.values) {
      expect(find.byKey(ValueKey('cropHandle-${handle.name}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('cropNextButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('cropNoCropButton')), findsOneWidget);
  });

  testWidgets('reset-to-full-frame button restores the quad after a drag', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        CropCorrectionScreen(
          projectId: 'proj1',
          pageId: 'p1',
          viewModel: viewModel,
        ),
      ),
    );
    await tester.runAsync(() async {
      var attempts = 0;
      while (viewModel.loading && attempts < 100) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        attempts++;
      }
    });
    await tester.pump();

    viewModel.dragCorner(CropCorner.topLeft, const Offset(0.3, 0.3));
    await tester.pump();
    expect(viewModel.quad, isNot(Quad.fullFrame));

    await tester.tap(find.byKey(const ValueKey('cropNoCropButton')));
    await tester.pump();
    expect(viewModel.quad, Quad.fullFrame);
  });
}

/// The widget tests above don't exercise `apply()`, so `enhance()` is never
/// actually invoked — this only needs to satisfy `CapturePageUseCase`'s
/// constructor.
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
