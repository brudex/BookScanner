import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/core/theme/app_theme.dart';
import 'package:bookscanner/ui/features/library/view_models/library_view_model.dart';
import 'package:bookscanner/ui/features/library/views/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_project_repository.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
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
  testWidgets('shows empty state when there are no projects', (tester) async {
    final repository = FakeProjectRepository();
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('libraryEmptyTitle'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('libraryList')), findsNothing);
  });

  testWidgets('shows project rows when projects exist', (tester) async {
    final repository = FakeProjectRepository();
    final now = DateTime.now();
    repository.seed([
      Project(
        id: 'p1',
        type: ProjectType.document,
        title: 'Tax Forms',
        metadata: const ProjectMetadata(),
        pageOrder: const [],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
    ]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('libraryList'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Tax Forms', skipOffstage: false), findsOneWidget);
  });

  testWidgets('search button opens from the home app bar', (tester) async {
    final repository = FakeProjectRepository();
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('librarySearchButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('libraryFavoritesButton')), findsOneWidget);
  });

  test('LibraryViewModel search filters projects by title', () async {
    final repository = FakeProjectRepository();
    final now = DateTime.now();
    repository.seed([
      Project(
        id: 'p1',
        type: ProjectType.document,
        title: 'Tax Forms',
        metadata: const ProjectMetadata(),
        pageOrder: const [],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
      Project(
        id: 'p2',
        type: ProjectType.book,
        title: 'Novel Scan',
        metadata: const ProjectMetadata(),
        pageOrder: const [],
        createdAt: now,
        updatedAt: now,
        processingState: ProcessingState.idle,
      ),
    ]);
    final viewModel = LibraryViewModel(projectRepository: repository);
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.projects.length, 2);

    viewModel.setSearchText('Novel');
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.projects.map((p) => p.title), ['Novel Scan']);
    viewModel.dispose();
  });

  testWidgets('home shows Popular Tools including Scan ID', (tester) async {
    final repository = FakeProjectRepository();
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('newScanFab')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeDockScans')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeQuickActionsList')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeScanDoc')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeScanId')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeAddFolder')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeGallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeImportFile')), findsOneWidget);
    expect(find.byKey(const ValueKey('homeToolBook')), findsOneWidget);
    expect(find.byKey(const ValueKey('librarySearchButton')), findsOneWidget);
  });

  testWidgets(
    "a project row's context menu offers Delete and no Recognize text",
    (tester) async {
      final repository = FakeProjectRepository();
      final now = DateTime.now();
      repository.seed([
        Project(
          id: 'p1',
          type: ProjectType.document,
          title: 'Tax Forms',
          metadata: const ProjectMetadata(),
          pageOrder: const ['page1', 'page2'],
          createdAt: now,
          updatedAt: now,
          processingState: ProcessingState.idle,
        ),
      ]);
      final viewModel = LibraryViewModel(projectRepository: repository);

      await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 pages', skipOffstage: false), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('libraryScroll')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('projectRowMenu')));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      // Removed: export runs OCR, so the row no longer offers it.
      expect(find.text('Recognize text'), findsNothing);
    },
  );

  testWidgets(
    "tapping Delete in a project row's context menu removes it from the visible list",
    (tester) async {
      final repository = FakeProjectRepository();
      final now = DateTime.now();
      repository.seed([
        Project(
          id: 'p1',
          type: ProjectType.document,
          title: 'Tax Forms',
          metadata: const ProjectMetadata(),
          pageOrder: const [],
          createdAt: now,
          updatedAt: now,
          processingState: ProcessingState.idle,
        ),
      ]);
      final viewModel = LibraryViewModel(projectRepository: repository);

      await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
      await tester.pumpAndSettle();
      expect(find.text('Tax Forms', skipOffstage: false), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('libraryScroll')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('projectRowMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Tax Forms', skipOffstage: false), findsNothing);
      expect(
        find.byKey(const ValueKey('libraryEmptyTitle'), skipOffstage: false),
        findsOneWidget,
      );
    },
  );
}
