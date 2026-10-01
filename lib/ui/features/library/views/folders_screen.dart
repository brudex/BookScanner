import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/folder.dart';
import '../../../../domain/repositories/folder_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/text_input_dialog.dart';
import 'project_list_row.dart';

/// Create/rename/delete folders (SPEC 6.8) and navigate into one to see its
/// projects, via [FolderContentsScreen].
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key, this.folderRepository});

  /// Injectable for widget tests; production code leaves this null and gets
  /// a real instance wired through the composition root.
  final FolderRepository? folderRepository;

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  late final FolderRepository _folderRepository;

  @override
  void initState() {
    super.initState();
    _folderRepository = widget.folderRepository ?? locator<FolderRepository>();
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(
      context: context,
      title: l10n.createFolder,
      label: l10n.folderNameLabel,
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _folderRepository.createFolder(trimmed);
  }

  Future<void> _renameFolder(Folder folder) async {
    final l10n = AppLocalizations.of(context);
    final name = await showTextInputDialog(
      context: context,
      title: l10n.rename,
      label: l10n.folderNameLabel,
      initialText: folder.name,
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _folderRepository.renameFolder(folder.id, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.homeShell(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.folders),
          actions: [
            IconButton(
              key: const ValueKey('createFolderButton'),
              icon: const Icon(LucideIcons.folderPlus),
              tooltip: l10n.createFolder,
              onPressed: _createFolder,
            ),
          ],
        ),
        body: StreamBuilder<List<Folder>>(
          stream: _folderRepository.watchFolders(),
          builder: (context, snapshot) {
            final folders = snapshot.data ?? const <Folder>[];
            if (folders.isEmpty) {
              return ProjectListEmptyState(
                icon: LucideIcons.folder,
                title: l10n.foldersEmptyTitle,
                subtitle: l10n.createFolder,
              );
            }
            return ListView.builder(
              key: const ValueKey('foldersList'),
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                return ListTile(
                  key: ValueKey('folder-${folder.id}'),
                  leading: const Icon(LucideIcons.folder),
                  title: Text(folder.name),
                  onTap: () =>
                      context.push(AppRoutes.folderContentsFor(folder.id)),
                  trailing: PopupMenuButton<String>(
                    key: ValueKey('folderMenu-${folder.id}'),
                    onSelected: (action) {
                      if (action == 'rename') _renameFolder(folder);
                      if (action == 'delete') {
                        _folderRepository.deleteFolder(folder.id);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.deleteFolder),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
