import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/core/theme/app_theme.dart';
import 'package:bookscanner/ui/features/library/view_models/library_view_model.dart';
import 'package:bookscanner/ui/features/library/views/favorites_screen.dart';
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

Project _project(String id, {required bool favorite}) {
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
    isFavorite: favorite,
  );
}

void main() {
  testWidgets('shows only favorited projects', (tester) async {
    final repository = FakeProjectRepository();
    repository.seed([
      _project('p1', favorite: true),
      _project('p2', favorite: false),
    ]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(FavoritesScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('Project p1'), findsOneWidget);
    expect(find.text('Project p2'), findsNothing);
  });

  testWidgets('shows the empty state when there are no favorites', (
    tester,
  ) async {
    final repository = FakeProjectRepository();
    repository.seed([_project('p1', favorite: false)]);
    final viewModel = LibraryViewModel(projectRepository: repository);

    await tester.pumpWidget(_wrap(FavoritesScreen(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('No favorites yet'), findsOneWidget);
  });
}
