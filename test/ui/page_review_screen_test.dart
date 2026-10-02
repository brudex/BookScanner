import 'dart:async';

import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/image_enhancement_provider.dart';
import 'package:bookscanner/domain/providers/page_detection_provider.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_path_allocator.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/use_cases/capture_page_use_case.dart';
import 'package:bookscanner/domain/use_cases/detect_page_anomalies_use_case.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/page_review/view_models/page_review_view_model.dart';
import 'package:bookscanner/ui/features/page_review/views/page_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// `CapturePageUseCase` is a required PageReviewViewModel dependency (for
// `revertToOriginal`) but no test in this file exercises that method yet, so
// these fakes are unused-but-present stand-ins, not exercised behavior.
class _FakeImageEnhancementProvider implements ImageEnhancementProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1.0.0');

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) =>
      throw UnimplementedError();

  @override
  Future<double> scoreQuality(String imagePath) => throw UnimplementedError();
}

class _FakePageDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake', adapterVersion: '1.0.0');

  @override
  Future<Quad?> detectQuad(String imagePath) => throw UnimplementedError();
}

class _FakePagePathAllocator implements PagePathAllocator {
  @override
  String originalPathFor(String pageId, {required String ext}) =>
      throw UnimplementedError();

  @override
  String processedPathFor(String pageId, {required String ext}) =>
      throw UnimplementedError();

  @override
  String thumbnailPathFor(String pageId) => throw UnimplementedError();

  @override
  String exportPathFor(String jobId, String extension) =>
      throw UnimplementedError();
}

/// A [PageRepository] whose `watchPages` stream only emits after
/// `emitPages` is called, so tests can reproduce the real-world race: the
/// screen mounts (and builds once) while pages are still loading, then
/// pages arrive asynchronously afterward.
class _FakePageRepository implements PageRepository {
  final _pages = <String, ScanPage>{};
  final _controller = StreamController<List<ScanPage>>.broadcast();

  void emitPages(String projectId) {
    _controller.add(
      _pages.values.where((p) => p.projectId == projectId).toList(),
    );
  }

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => _controller.stream;

  @override
  Future<List<ScanPage>> getPages(String projectId) async =>
      _pages.values.where((p) => p.projectId == projectId).toList();

  @override
  Future<ScanPage?> getPage(String pageId) async => _pages[pageId];

  @override
  Future<void> addPage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<void> updatePage(ScanPage page) async => _pages[page.id] = page;

  @override
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Future<void> deletePage(String pageId) async => _pages.remove(pageId);

  @override
  Future<void> duplicatePage(String pageId) async {}
}

class _FakeOcrRepository implements OcrRepository {
  @override
  Future<List<OcrBlock>> getBlocks(String pageId) async => const [];

  @override
  Stream<List<OcrBlock>> watchBlocks(String pageId) => const Stream.empty();

  @override
  Future<void> saveBlocks(String pageId, List<OcrBlock> blocks) async {}

  @override
  Future<void> correctBlock(
    String pageId,
    String blockId,
    String newText,
  ) async {}

  @override
  Future<bool> hasOcr(String pageId) async => false;

  @override
  Future<List<String>> searchPages(String projectId, String query) async =>
      const [];
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
  testWidgets(
    'the Export button becomes enabled once pages load asynchronously after the first build',
    (tester) async {
      final pageRepository = _FakePageRepository();
      await pageRepository.addPage(
        const ScanPage(
          id: 'p1',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: '/tmp/p1.jpg',
          status: PageStatus.ready,
        ),
      );
      final viewModel = PageReviewViewModel(
        projectId: 'proj1',
        pageRepository: pageRepository,
        detectAnomaliesUseCase: DetectPageAnomaliesUseCase(
          pageRepository: pageRepository,
          ocrRepository: _FakeOcrRepository(),
        ),
        capturePageUseCase: CapturePageUseCase(
          pageRepository: pageRepository,
          enhancementProvider: _FakeImageEnhancementProvider(),
          detectionProvider: _FakePageDetectionProvider(),
          fileStorage: _FakePagePathAllocator(),
        ),
      );

      await tester.pumpWidget(
        _wrap(PageReviewScreen(projectId: 'proj1', viewModel: viewModel)),
      );

      // First frame: pages haven't arrived yet (still `loading`), so the
      // Export button must start disabled.
      var exportButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('reviewExportButton')),
      );
      expect(exportButton.onPressed, isNull);

      // Pages arrive asynchronously (this is what a real `watchPages`
      // stream does after its first query completes).
      pageRepository.emitPages('proj1');
      await tester.pump();

      // Regression check: the Export button previously never re-evaluated
      // `_viewModel.pages.isEmpty` because it sat outside a
      // `ListenableBuilder`, so it stayed disabled forever even once pages
      // genuinely loaded.
      exportButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('reviewExportButton')),
      );
      expect(exportButton.onPressed, isNotNull);
      final cameraSize = tester.getSize(
        find.byKey(const ValueKey('reviewAddCamera')),
      );
      final gallerySize = tester.getSize(
        find.byKey(const ValueKey('reviewAddGallery')),
      );
      final filesSize = tester.getSize(
        find.byKey(const ValueKey('reviewAddFromFiles')),
      );
      expect(filesSize, cameraSize);
      expect(filesSize, gallerySize);
      await tester.tap(find.byKey(const ValueKey('reviewExportButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reviewExportPdf')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reviewExportMarkdown')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reviewExportEpub')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewPdfOptions')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewMarkdownOptions')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reviewExportMarkdown')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reviewPdfOptions')), findsNothing);
      expect(
        find.byKey(const ValueKey('reviewMarkdownOptions')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('reviewExportEpub')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reviewMarkdownOptions')), findsNothing);
      expect(find.byKey(const ValueKey('reviewEpubOptions')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewAddCamera')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewAddGallery')), findsOneWidget);
      expect(find.byKey(const ValueKey('reviewAddFromFiles')), findsOneWidget);
    },
  );

  testWidgets(
    'toggling grid view swaps the reorderable list for a browse-only grid',
    (tester) async {
      final pageRepository = _FakePageRepository();
      await pageRepository.addPage(
        const ScanPage(
          id: 'p1',
          projectId: 'proj1',
          sequence: 0,
          originalImagePath: '/tmp/p1.jpg',
          status: PageStatus.ready,
        ),
      );
      final viewModel = PageReviewViewModel(
        projectId: 'proj1',
        pageRepository: pageRepository,
        detectAnomaliesUseCase: DetectPageAnomaliesUseCase(
          pageRepository: pageRepository,
          ocrRepository: _FakeOcrRepository(),
        ),
        capturePageUseCase: CapturePageUseCase(
          pageRepository: pageRepository,
          enhancementProvider: _FakeImageEnhancementProvider(),
          detectionProvider: _FakePageDetectionProvider(),
          fileStorage: _FakePagePathAllocator(),
        ),
      );

      await tester.pumpWidget(
        _wrap(PageReviewScreen(projectId: 'proj1', viewModel: viewModel)),
      );
      pageRepository.emitPages('proj1');
      await tester.pump();

      expect(find.byKey(const ValueKey('pageReviewList')), findsOneWidget);
      expect(find.byKey(const ValueKey('pageReviewGrid')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reviewToggleGridButton')));
      await tester.pump();

      expect(find.byKey(const ValueKey('pageReviewList')), findsNothing);
      expect(find.byKey(const ValueKey('pageReviewGrid')), findsOneWidget);
      expect(find.byKey(const ValueKey('page-p1')), findsOneWidget);
    },
  );
}
