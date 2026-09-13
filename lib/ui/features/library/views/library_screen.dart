import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/service_locator.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../view_models/library_view_model.dart';
import 'project_list_row.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.viewModel});

  /// Injectable for widget tests; production code leaves this null and gets
  /// a real instance wired through the composition root.
  final LibraryViewModel? viewModel;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        LibraryViewModel(projectRepository: locator<ProjectRepository>());
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle, key: const ValueKey('libraryTitle')),
        actions: [
          IconButton(
            key: const ValueKey('librarySettingsButton'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
            tooltip: l10n.settingsTitle,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  key: const ValueKey('librarySearchField'),
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onChanged: _viewModel.setSearchText,
                ),
              ),
              Expanded(child: _buildBody(context, l10n)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('newScanFab'),
        onPressed: () => context.push(AppRoutes.newScan),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(l10n.newScan),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_viewModel.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null) {
      return Center(child: Text('${_viewModel.error}'));
    }
    if (_viewModel.projects.isEmpty) {
      return _EmptyLibrary(l10n: l10n);
    }
    return ListView.builder(
      key: const ValueKey('libraryList'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _viewModel.projects.length,
      itemBuilder: (context, index) {
        final project = _viewModel.projects[index];
        return ProjectListRow(
          key: ValueKey('project-${project.id}'),
          project: project,
          onTap: () => context.push(AppRoutes.pageReviewFor(project.id)),
          onFavoriteToggle: () => _viewModel.toggleFavorite(project),
          onDelete: () => _viewModel.moveToTrash(project),
        );
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.document_scanner_outlined,
              size: 72,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.libraryEmptyTitle,
              key: const ValueKey('libraryEmptyTitle'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.libraryEmptySubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
