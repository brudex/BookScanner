import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/folder.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/folder_repository.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../view_models/library_view_model.dart';
import 'project_list_row.dart';

/// Projects assigned to one folder (SPEC 6.8), reached from [FoldersScreen].
class FolderContentsScreen extends StatefulWidget {
  const FolderContentsScreen({
    super.key,
    required this.folderId,
    this.viewModel,
    this.folderRepository,
  });

  final String folderId;

  /// Injectable for widget tests; production code leaves these null and
  /// gets real instances wired through the composition root.
  final LibraryViewModel? viewModel;
  final FolderRepository? folderRepository;

  @override
  State<FolderContentsScreen> createState() => _FolderContentsScreenState();
}

class _FolderContentsScreenState extends State<FolderContentsScreen> {
  late final LibraryViewModel _viewModel;
  late final FolderRepository _folderRepository;

  @override
  void initState() {
    super.initState();
    _folderRepository = widget.folderRepository ?? locator<FolderRepository>();
    _viewModel =
        widget.viewModel ??
        LibraryViewModel(
          projectRepository: locator<ProjectRepository>(),
          pageRepository: locator<PageRepository>(),
          folderId: widget.folderId,
        );
    if (_viewModel.folderId != widget.folderId) {
      _viewModel.setFolderId(widget.folderId);
    }
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
      data: AppTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: StreamBuilder<List<Folder>>(
            stream: _folderRepository.watchFolders(),
            builder: (context, snapshot) {
              final folders = snapshot.data ?? const <Folder>[];
              Folder? match;
              for (final folder in folders) {
                if (folder.id == widget.folderId) {
                  match = folder;
                  break;
                }
              }
              return Text(match?.name ?? l10n.folders);
            },
          ),
        ),
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final projects = _viewModel.projects;
            if (projects.isEmpty) {
              return ProjectListEmptyState(
                icon: LucideIcons.folder,
                title: l10n.libraryEmptyTitle,
                subtitle: l10n.libraryEmptySubtitle,
              );
            }
            return ListView(
              key: const ValueKey('folderContentsList'),
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              children: [
                for (final project in projects)
                  ProjectListRow(
                    key: ValueKey('folder-project-${project.id}'),
                    project: project,
                    thumbnailPath: _viewModel.thumbnailFor(project.id),
                    onTap: () =>
                        context.push(AppRoutes.pageReviewFor(project.id)),
                    onFavoriteToggle: () => _viewModel.toggleFavorite(project),
                    onDelete: () => _viewModel.moveToTrash(project),
                    onShare: () =>
                        context.push(AppRoutes.exportFor(project.id)),
                    onRename: () => _renameProject(project),
                    onMoveToFolder: () async {
                      await _viewModel.moveToFolder(project, null);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
