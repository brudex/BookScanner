import 'package:bookscanner/domain/models/geometry.dart';
import 'package:bookscanner/domain/models/ocr_block.dart';
import 'package:bookscanner/domain/models/provider_info.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:bookscanner/domain/providers/ocr_provider.dart';
import 'package:bookscanner/domain/repositories/ocr_repository.dart';
import 'package:bookscanner/domain/repositories/page_repository.dart';
import 'package:bookscanner/domain/repositories/settings_repository.dart';
import 'package:bookscanner/domain/use_cases/run_ocr_use_case.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/ocr_review/view_models/ocr_review_view_model.dart';
import 'package:bookscanner/ui/features/ocr_review/views/ocr_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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
  Future<void> reorderPages(String projectId, List<String> order) async {}

  @override
  Stream<List<ScanPage>> watchPages(String projectId) => const Stream.empty();
}

class _FakeOcrRepository implements OcrRepository {
  final _byPage = <String, List<OcrBlock>>{};

  @override
  Future<List<OcrBlock>> getBlocks(String pageId) async =>
      _byPage[pageId] ?? const [];

  @override
  Stream<List<OcrBlock>> watchBlocks(String pageId) => const Stream.empty();

  @override
  Future<void> saveBlocks(String pageId, List<OcrBlock> blocks) async {
    _byPage[pageId] = blocks;
  }

  @override
  Future<void> correctBlock(
    String pageId,
    String blockId,
    String newText,
  ) async {
    final blocks = _byPage[pageId];
    if (blocks == null) return;
    _byPage[pageId] = [
      for (final b in blocks)
        if (b.id == blockId)
          b.withCorrection(newText, DateTime.now().millisecondsSinceEpoch)
        else
          b,
    ];
  }

  @override
  Future<bool> hasOcr(String pageId) async =>
      _byPage[pageId]?.isNotEmpty ?? false;

  @override
  Future<List<String>> searchPages(String projectId, String query) async =>
      const [];
}

class _FakeOcrProvider implements OcrProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-ocr', adapterVersion: '1');

  @override
  bool get requiresNetwork => false;

  @override
  Future<Set<String>> supportedLanguages() async => {'en'};

  @override
  Future<OcrResult> recognize(OcrRequest request) async => OcrResult(
    blocks: [
      OcrBlock(
        id: '',
        pageId: '',
        boundingPolygon: const Polygon([
          Point2D(x: 0.1, y: 0.1),
          Point2D(x: 0.9, y: 0.1),
          Point2D(x: 0.9, y: 0.14),
          Point2D(x: 0.1, y: 0.14),
        ]),
        text: 'Recognized heading',
        confidence: 0.95,
        language: 'en',
        blockType: BlockType.unknown,
        readingOrder: 0,
      ),
    ],
    providerInfo: info,
  );
}

/// Regression fixture for a real bug found during on-device testing: a page
/// with no actual text (e.g. a photo of a room) legitimately recognizes
/// zero blocks, which must not be shown as "OCR has not been run yet"
/// forever.
class _FakeEmptyOcrProvider implements OcrProvider {
  @override
  ProviderInfo get info =>
      const ProviderInfo(providerName: 'fake-ocr-empty', adapterVersion: '1');

  @override
  bool get requiresNetwork => false;

  @override
  Future<Set<String>> supportedLanguages() async => {'en'};

  @override
  Future<OcrResult> recognize(OcrRequest request) async =>
      OcrResult(blocks: const [], providerInfo: info);
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  Future<void> updateSettings(AppSettings settings) async {}

  @override
  Stream<AppSettings> watchSettings() => Stream.value(const AppSettings());
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
  late _FakePageRepository pageRepository;
  late _FakeOcrRepository ocrRepository;
  late RunOcrUseCase runOcrUseCase;

  setUp(() async {
    pageRepository = _FakePageRepository();
    ocrRepository = _FakeOcrRepository();
    runOcrUseCase = RunOcrUseCase(
      pageRepository: pageRepository,
      ocrRepository: ocrRepository,
      ocrProvider: _FakeOcrProvider(),
      settingsRepository: _FakeSettingsRepository(),
    );
    await pageRepository.addPage(
      const ScanPage(
        id: 'p1',
        projectId: 'proj1',
        sequence: 0,
        originalImagePath: '/tmp/p1.jpg',
        status: PageStatus.ready,
      ),
    );
  });

  testWidgets(
    'shows the empty state with a Run OCR button before OCR has run',
    (tester) async {
      final viewModel = OcrReviewViewModel(
        pageId: 'p1',
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        runOcrUseCase: runOcrUseCase,
      );

      await tester.pumpWidget(
        _wrap(
          OcrReviewScreen(
            projectId: 'proj1',
            pageId: 'p1',
            viewModel: viewModel,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('ocrReviewEmptyState')), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrRunButton')), findsOneWidget);
    },
  );

  testWidgets('running OCR replaces the empty state with recognized blocks', (
    tester,
  ) async {
    final viewModel = OcrReviewViewModel(
      pageId: 'p1',
      pageRepository: pageRepository,
      ocrRepository: ocrRepository,
      runOcrUseCase: runOcrUseCase,
    );

    await tester.pumpWidget(
      _wrap(
        OcrReviewScreen(projectId: 'proj1', pageId: 'p1', viewModel: viewModel),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ocrRunButton')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('ocrBlockList')), findsOneWidget);
    expect(find.text('Recognized heading'), findsOneWidget);
    expect(find.byKey(const ValueKey('ocrRerunButton')), findsOneWidget);
  });

  testWidgets(
    'a page with no recognizable text shows "no text found", not "not run yet"',
    (tester) async {
      final emptyRunOcrUseCase = RunOcrUseCase(
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        ocrProvider: _FakeEmptyOcrProvider(),
        settingsRepository: _FakeSettingsRepository(),
      );
      final viewModel = OcrReviewViewModel(
        pageId: 'p1',
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        runOcrUseCase: emptyRunOcrUseCase,
      );

      await tester.pumpWidget(
        _wrap(
          OcrReviewScreen(
            projectId: 'proj1',
            pageId: 'p1',
            viewModel: viewModel,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ocrRunButton')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('ocrNoTextFoundState')), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrReviewEmptyState')), findsNothing);
      expect(find.byKey(const ValueKey('ocrRunButton')), findsNothing);
      expect(viewModel.hasRun, isTrue);

      // Re-opening the page (a fresh view model, simulating navigating away
      // and back) must still recognize that OCR already ran, even though
      // it found zero blocks.
      final reloaded = OcrReviewViewModel(
        pageId: 'p1',
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        runOcrUseCase: emptyRunOcrUseCase,
      );
      await reloaded.initialize();
      expect(reloaded.hasRun, isTrue);
    },
  );

  testWidgets(
    'tapping a block opens an edit dialog and correcting it persists the new text',
    (tester) async {
      await ocrRepository.saveBlocks('p1', [
        const OcrBlock(
          id: 'b1',
          pageId: 'p1',
          boundingPolygon: Polygon([
            Point2D(x: 0.1, y: 0.1),
            Point2D(x: 0.9, y: 0.1),
            Point2D(x: 0.9, y: 0.14),
            Point2D(x: 0.1, y: 0.14),
          ]),
          text: 'Origianl mistake',
          confidence: 0.3,
          language: 'en',
          blockType: BlockType.paragraph,
          readingOrder: 0,
        ),
      ]);
      // Simulate a page that already went through a real OCR run in a
      // previous session (`RunOcrUseCase` always records this stage,
      // regardless of block count -- see the "no text found" test above).
      final existingPage = (await pageRepository.getPage('p1'))!;
      await pageRepository.updatePage(
        existingPage.copyWith(
          stages: {
            ...existingPage.stages,
            PipelineStage.ocr: StageRecord(
              version: 1,
              providerInfo: const ProviderInfo(
                providerName: 'fake-ocr',
                adapterVersion: '1',
              ),
              completedAtMs: 0,
            ),
          },
        ),
      );
      final viewModel = OcrReviewViewModel(
        pageId: 'p1',
        pageRepository: pageRepository,
        ocrRepository: ocrRepository,
        runOcrUseCase: runOcrUseCase,
      );

      await tester.pumpWidget(
        _wrap(
          OcrReviewScreen(
            projectId: 'proj1',
            pageId: 'p1',
            viewModel: viewModel,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Origianl mistake'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ocrBlock-b1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ocrEditBlockField')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('ocrEditBlockField')),
        'Original mistake',
      );
      await tester.tap(find.byKey(const ValueKey('ocrEditBlockSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Original mistake'), findsOneWidget);
      final saved = await ocrRepository.getBlocks('p1');
      expect(saved.single.text, 'Original mistake');
      expect(saved.single.wasCorrected, isTrue);
    },
  );
}
