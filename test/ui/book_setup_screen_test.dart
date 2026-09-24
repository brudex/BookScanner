import 'package:bookscanner/domain/models/project.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/routing/app_router.dart';
import 'package:bookscanner/ui/features/library/view_models/book_setup_view_model.dart';
import 'package:bookscanner/ui/features/library/views/book_setup_screen.dart';
import 'package:bookscanner/ui/features/library/views/new_scan_sheet_route.dart';
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
  late FakeProjectRepository repository;
  late Project project;

  setUp(() async {
    repository = FakeProjectRepository();
    project = await repository.createProject(
      type: ProjectType.book,
      title: 'Book',
    );
  });

  test('New Scan sends books to setup and documents to capture', () {
    expect(
      NewScanSheetRoute.afterCreate(project),
      AppRoutes.bookSetupFor(project.id),
    );
    expect(
      NewScanSheetRoute.afterCreate(
        Project(
          id: 'doc1',
          type: ProjectType.document,
          title: 'Document',
          metadata: const ProjectMetadata(),
          pageOrder: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          processingState: ProcessingState.idle,
        ),
      ),
      AppRoutes.captureFor('doc1'),
    );
  });

  test('save persists title after copyright ack (other fields ignored)', () async {
    final viewModel = BookSetupViewModel(
      projectId: project.id,
      projectRepository: repository,
    );
    await viewModel.initialize();
    viewModel.setTitle('The Odyssey');
    viewModel.setAuthor('Homer');

    expect(await viewModel.save(), isFalse);

    viewModel.setCopyrightAcknowledged(true);
    expect(await viewModel.save(), isTrue);

    final saved = await repository.getProject(project.id);
    expect(saved!.title, 'The Odyssey');
    // Author and other metadata are not written from this screen.
    expect(saved.metadata.author, isNull);
  });

  testWidgets('shows title + copyright only, Continue gated on ack', (
    tester,
  ) async {
    final viewModel = BookSetupViewModel(
      projectId: project.id,
      projectRepository: repository,
    );
    await tester.pumpWidget(
      _wrap(BookSetupScreen(projectId: project.id, viewModel: viewModel)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('bookSetupTitleField')), findsOneWidget);
    expect(find.byKey(const ValueKey('bookSetupAuthorField')), findsNothing);
    expect(find.byKey(const ValueKey('bookSetupScanMode')), findsNothing);
    expect(
      find.byKey(const ValueKey('bookSetupCopyrightNotice')),
      findsOneWidget,
    );

    final continueButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('bookSetupContinueButton')),
    );
    expect(continueButton.onPressed, isNull);

    final ack = find.byKey(const ValueKey('bookSetupCopyrightAck'));
    await tester.ensureVisible(ack);
    await tester.tap(ack);
    await tester.pump();

    final enabled = tester.widget<FilledButton>(
      find.byKey(const ValueKey('bookSetupContinueButton')),
    );
    expect(enabled.onPressed, isNotNull);
  });
}
