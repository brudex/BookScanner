import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../domain/models/project.dart';
import '../../../../l10n/gen/app_localizations.dart';

enum ProjectRowAction { delete, recognizeText }

class ProjectListRow extends StatelessWidget {
  const ProjectListRow({
    super.key,
    required this.project,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDelete,
    this.thumbnailPath,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;
  final String? thumbnailPath;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _Thumbnail(path: thumbnailPath, type: project.type),
        ),
      ),
      title: Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.projectPageCount(project.pageOrder.length)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('projectFavoriteButton'),
            icon: Icon(
              project.isFavorite ? Icons.star : Icons.star_border,
              color: project.isFavorite ? Colors.amber : null,
            ),
            onPressed: onFavoriteToggle,
          ),
          PopupMenuButton<ProjectRowAction>(
            key: const ValueKey('projectRowMenu'),
            tooltip: l10n.projectRowMenu,
            onSelected: (action) {
              switch (action) {
                case ProjectRowAction.delete:
                  onDelete();
                case ProjectRowAction.recognizeText:
                // Disabled below -- PopupMenuItem never fires onSelected
                // for a disabled item, so this case is unreachable.
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ProjectRowAction.recognizeText,
                // Whole-project text extraction (distinct from the
                // existing per-page "Recognize text" action in Page
                // Review) is not implemented yet -- shown so users know
                // it's coming rather than hiding it, but disabled so it
                // can't silently no-op.
                enabled: false,
                child: Text(l10n.ocrAction),
              ),
              PopupMenuItem(
                value: ProjectRowAction.delete,
                child: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.type});

  final String? path;
  final ProjectType type;

  @override
  Widget build(BuildContext context) {
    if (path != null && File(path!).existsSync()) {
      return Image.file(File(path!), fit: BoxFit.cover);
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          type == ProjectType.book
              ? Icons.menu_book_outlined
              : Icons.description_outlined,
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
