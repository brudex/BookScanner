import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../view_models/library_view_model.dart';
import 'project_list_row.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.viewModel});

  /// Injectable for widget tests; production code leaves this null and gets
  /// a real instance wired through the composition root.
  final LibraryViewModel? viewModel;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late final LibraryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        LibraryViewModel(
          projectRepository: locator<ProjectRepository>(),
          pageRepository: locator<PageRepository>(),
        );
    if (!_viewModel.favoritesOnly) _viewModel.setFavoritesOnly(true);
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<void> _renameProject(Project project) async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(
      context: context,
      title: l10n.rename,
      label: l10n.nameScanLabel,
      initialText: project.title,
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _viewModel.renameProject(project, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.homeShell(),
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.favorites)),
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final projects = _viewModel.projects;
            if (projects.isEmpty) {
              return ProjectListEmptyState(
                icon: LucideIcons.star,
                title: l10n.favoritesEmptyTitle,
                subtitle: l10n.favoritesEmptySubtitle,
              );
            }
            return ListView(
              key: const ValueKey('favoritesList'),
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              children: [
                for (final project in projects)
                  ProjectListRow(
                    key: ValueKey('favorite-${project.id}'),
                    project: project,
                    thumbnailPath: _viewModel.thumbnailFor(project.id),
                    onTap: () =>
                        context.push(AppRoutes.pageReviewFor(project.id)),
                    onFavoriteToggle: () => _viewModel.toggleFavorite(project),
                    onDelete: () => _viewModel.moveToTrash(project),
                    onShare: () =>
                        context.push(AppRoutes.exportFor(project.id)),
                    onRename: () => _renameProject(project),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

