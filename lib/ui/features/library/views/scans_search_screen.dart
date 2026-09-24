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

/// Full-library search — opened from Home's search control.
class ScansSearchScreen extends StatefulWidget {
  const ScansSearchScreen({super.key, this.viewModel});

  final LibraryViewModel? viewModel;

  @override
  State<ScansSearchScreen> createState() => _ScansSearchScreenState();
}

class _ScansSearchScreenState extends State<ScansSearchScreen> {
  late final LibraryViewModel _viewModel;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
    _viewModel =
        widget.viewModel ??
        LibraryViewModel(
          projectRepository: locator<ProjectRepository>(),
          pageRepository: locator<PageRepository>(),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
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
    return Scaffold(
      key: const ValueKey('scansSearchScreen'),
      backgroundColor: AppTheme.homeBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.homeBackground,
        foregroundColor: AppTheme.homeText,
        elevation: 0,
        title: Text(
          l10n.scansSearchTitle,
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          if (_viewModel.loading && _viewModel.projects.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = _viewModel.projects;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  key: const ValueKey('scansSearchField'),
                  controller: _searchController,
                  focusNode: _searchFocus,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.homeText,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    hintStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      color: AppTheme.homeMuted,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      LucideIcons.search,
                      color: AppTheme.homeMuted,
                      size: 18,
                    ),
                    filled: true,
                    fillColor: AppTheme.homeCard,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppTheme.homeHairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: AppTheme.accent),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                  ),
                  onChanged: _viewModel.setSearchText,
                ),
              ),
              Expanded(
                child: projects.isEmpty
                    ? Center(
                        child: Text(
                          _viewModel.searchText.isEmpty
                              ? l10n.libraryEmptyTitle
                              : l10n.searchNoResults,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: AppTheme.homeMuted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: projects.length,
                        itemBuilder: (context, index) {
                          final project = projects[index];
                          return ProjectListRow(
                            key: ValueKey('scans-project-${project.id}'),
                            project: project,
                            thumbnailPath: _viewModel.thumbnailFor(project.id),
                            onTap: () => context.push(
                              AppRoutes.pageReviewFor(project.id),
                            ),
                            onFavoriteToggle: () =>
                                _viewModel.toggleFavorite(project),
                            onDelete: () => _viewModel.moveToTrash(project),
                            onShare: () =>
                                context.push(AppRoutes.exportFor(project.id)),
                            onRename: () => _renameProject(project),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
