import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/library_view_model.dart';
import 'project_list_row.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.viewModel});

  /// Injectable for widget tests; production code leaves this null and gets
  /// a real instance wired through the composition root.
  final LibraryViewModel? viewModel;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late final LibraryViewModel _viewModel;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        LibraryViewModel(
          projectRepository: locator<ProjectRepository>(),
          pageRepository: locator<PageRepository>(),
        );
    if (!_viewModel.includeTrashed) _viewModel.setIncludeTrashed(true);
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Future<void> _bulkRestore() async {
    final projects = _selectedProjects();
    for (final project in projects) {
      await _viewModel.restoreFromTrash(project);
    }
    setState(_selectedIds.clear);
  }

  Future<void> _bulkDeleteForever() async {
    final l10n = AppLocalizations.of(context);
    final projects = _selectedProjects();
    if (projects.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteForeverConfirmTitle),
        content: Text(l10n.deleteForeverConfirmBodySelected(projects.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('trashBulkDeleteConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              l10n.deleteForeverAction,
              style: const TextStyle(color: Color(0xFFE05353)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final project in projects) {
      await _viewModel.deletePermanently(project);
    }
    setState(_selectedIds.clear);
  }

  List<Project> _selectedProjects() => _viewModel.projects
      .where((project) => _selectedIds.contains(project.id))
      .toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.light(),
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.trash)),
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_viewModel.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final projects = _viewModel.projects;
            if (projects.isEmpty) {
              return ProjectListEmptyState(
                icon: LucideIcons.trash2,
                title: l10n.trashEmptyTitle,
                subtitle: l10n.trashEmptySubtitle,
              );
            }
            final selecting = _selectedIds.isNotEmpty;
            return ListView(
              key: const ValueKey('trashList'),
              padding: EdgeInsets.only(
                top: 8,
                bottom: selecting ? 88 : 12,
              ),
              children: [
                for (final project in projects)
                  ProjectListRow(
                    key: ValueKey('trashed-${project.id}'),
                    project: project,
                    thumbnailPath: _viewModel.thumbnailFor(project.id),
                    selected: _selectedIds.contains(project.id),
                    selectionMode: selecting,
                    onTap: () {
                      if (selecting) _toggleSelected(project.id);
                    },
                    onLongPress: () => _toggleSelected(project.id),
                    onRestore: () => _viewModel.restoreFromTrash(project),
                    onDeleteForever: () =>
                        _viewModel.deletePermanently(project),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            if (_selectedIds.isEmpty || _viewModel.projects.isEmpty) {
              return const SizedBox.shrink();
            }
            return SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _TrashSelectionBar(
                l10n: l10n,
                count: _selectedIds.length,
                onCancel: () => setState(_selectedIds.clear),
                onRestore: _bulkRestore,
                onDeleteForever: _bulkDeleteForever,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrashSelectionBar extends StatelessWidget {
  const _TrashSelectionBar({
    required this.l10n,
    required this.count,
    required this.onCancel,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final AppLocalizations l10n;
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.homeDock,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppTheme.cardShadow,
        border: Border.all(color: AppTheme.homeHairline),
      ),
      child: Material(
        color: AppTheme.homeDock,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('trashSelectionCancel'),
                onPressed: onCancel,
                icon: const Icon(LucideIcons.x, color: AppTheme.homeIcon),
              ),
              Expanded(
                child: Text(
                  l10n.selectedCount(count),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.homeText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('trashSelectionRestore'),
                onPressed: onRestore,
                tooltip: l10n.restoreAction,
                icon: const Icon(
                  LucideIcons.rotateCcw,
                  color: AppTheme.accentDeep,
                ),
              ),
              IconButton(
                key: const ValueKey('trashSelectionDeleteForever'),
                onPressed: onDeleteForever,
                tooltip: l10n.deleteForeverAction,
                icon: const Icon(
                  LucideIcons.trash2,
                  color: Color(0xFFE05353),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
