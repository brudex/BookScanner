import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/core/theme/app_theme.dart';
import 'package:bookscanner/ui/features/library/view_models/library_view_model.dart';
import 'package:bookscanner/ui/features/library/views/trash_screen.dart';
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

Project _project(String id, {required bool trashed}) {
  final now = DateTime.now();
  return Project(
    id: id,
    type: ProjectType.document,
    title: 'Project $id',
    metadata: const ProjectMetadata(),
    pageOrder: const [],
    createdAt: now,
    updatedAt: now,
    processingState: ProcessingState.idle,
    isTrashed: trashed,
  );
}

void main() {
  testWidgets('shows only trashed projects', (tester) async {
    final repository = FakeProjectRepository();
    repository.seed([
      _project('p1', trashed: true),
      _project('p2', trashed: false),
    ]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(TrashScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('Project p1'), findsOneWidget);
    expect(find.text('Project p2'), findsNothing);
  });

  testWidgets('shows the empty state when trash is empty', (tester) async {
    final repository = FakeProjectRepository();
    repository.seed([_project('p1', trashed: false)]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(TrashScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('Trash is empty'), findsOneWidget);
  });

  testWidgets('restoring a project removes it from the trash list', (
    tester,
  ) async {
    final repository = FakeProjectRepository();
    repository.seed([_project('p1', trashed: true)]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(TrashScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();
    expect(find.text('Project p1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('projectRestoreButton')));
    await tester.pumpAndSettle();

    expect(find.text('Project p1'), findsNothing);
    expect(find.text('Trash is empty'), findsOneWidget);
  });

  testWidgets(
    'deleting forever asks for confirmation and then removes the project',
    (tester) async {
      final repository = FakeProjectRepository();
      repository.seed([_project('p1', trashed: true)]);
      final viewModel = LibraryViewModel(projectRepository: repository);

      await tester.pumpWidget(_wrap(TrashScreen(viewModel: viewModel)));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('projectDeleteForeverButton')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete forever?'), findsOneWidget);
      await tester.tap(find.text('Delete Forever'));
      await tester.pumpAndSettle();

      expect(find.text('Project p1'), findsNothing);
      expect(find.text('Trash is empty'), findsOneWidget);
    },
  );

  testWidgets('long-press enters selection and bulk restore recovers both', (
    tester,
  ) async {
    final repository = FakeProjectRepository();
    repository.seed([
      _project('p1', trashed: true),
      _project('p2', trashed: true),
    ]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(TrashScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Project p1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('trashSelectionRestore')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('projectSelected-p1')),
      findsOneWidget,
    );

    await tester.tap(find.text('Project p2'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('trashSelectionRestore')));
    await tester.pumpAndSettle();

    expect(find.text('Project p1'), findsNothing);
    expect(find.text('Project p2'), findsNothing);
    expect(find.text('Trash is empty'), findsOneWidget);
  });

  testWidgets('bulk delete forever confirms once then removes selected', (
    tester,
  ) async {
    final repository = FakeProjectRepository();
    repository.seed([
      _project('p1', trashed: true),
      _project('p2', trashed: true),
      _project('p3', trashed: true),
    ]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(TrashScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Project p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project p2'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('trashSelectionDeleteForever')));
    await tester.pumpAndSettle();

    expect(find.text('Delete forever?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trashBulkDeleteConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Project p1'), findsNothing);
    expect(find.text('Project p2'), findsNothing);
    expect(find.text('Project p3'), findsOneWidget);
  });
}
