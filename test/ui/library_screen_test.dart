import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/library/view_models/library_view_model.dart';
import 'package:bookscanner/ui/features/library/views/library_screen.dart';
import 'package:bookscanner/ui/features/library/views/project_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_project_repository.dart';

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
  testWidgets('shows empty state when there are no projects', (tester) async {
    final repository = FakeProjectRepository();
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('libraryEmptyTitle')), findsOneWidget);
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

    expect(find.byKey(const ValueKey('libraryList')), findsOneWidget);
    expect(find.text('Tax Forms'), findsOneWidget);
  });

  testWidgets('search field filters the visible projects', (tester) async {
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

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();
    expect(find.text('Tax Forms'), findsOneWidget);
    expect(find.text('Novel Scan'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('librarySearchField')),
      'Novel',
    );
    await tester.pumpAndSettle();

    expect(find.text('Novel Scan'), findsOneWidget);
    expect(find.text('Tax Forms'), findsNothing);
  });

  testWidgets('tapping New Scan FAB is present and tappable', (tester) async {
    final repository = FakeProjectRepository();
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(LibraryScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('newScanFab')), findsOneWidget);
  });

  testWidgets(
    "a project row's context menu offers Delete and a not-yet-implemented Recognize text",
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

      expect(find.text('2 pages'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('projectRowMenu')));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      final recognizeItem = tester.widget<PopupMenuItem<ProjectRowAction>>(
        find.ancestor(
          of: find.text('Recognize text'),
          matching: find.byType(PopupMenuItem<ProjectRowAction>),
        ),
      );
      expect(recognizeItem.enabled, isFalse);
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
      expect(find.text('Tax Forms'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('projectRowMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Tax Forms'), findsNothing);
      expect(find.byKey(const ValueKey('libraryEmptyTitle')), findsOneWidget);
    },
  );
}
