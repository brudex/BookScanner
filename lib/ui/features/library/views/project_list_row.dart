import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/project.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/page_image.dart';

enum ProjectRowAction {
  share,
  rename,
  moveToFolder,
  editTags,
  delete,
  recognizeText,
}

class ProjectListRow extends StatelessWidget {
  const ProjectListRow({
    super.key,
    required this.project,
    required this.onTap,
    this.onFavoriteToggle,
    this.onDelete,
    this.onShare,
    this.onRename,
    this.onRestore,
    this.onDeleteForever,
    this.onLongPress,
    this.onMoveToFolder,
    this.onEditTags,
    this.thumbnailPath,
    this.selected = false,
    this.selectionMode = false,
  }) : assert(
         (onFavoriteToggle != null && onDelete != null) ||
             (onRestore != null && onDeleteForever != null),
         'Either the active-project actions (onFavoriteToggle, onDelete) or '
         'the trashed-project actions (onRestore, onDeleteForever) must be '
         'provided.',
       );

  final Project project;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onRename;
  final VoidCallback? onRestore;
  final VoidCallback? onDeleteForever;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoveToFolder;
  final VoidCallback? onEditTags;
  final String? thumbnailPath;
  final bool selected;
  final bool selectionMode;

  bool get _trashed => onRestore != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timestamp = DateFormat(
      'd MMM · h:mma',
    ).format(project.updatedAt.toLocal());
    final meta =
        '${l10n.projectPageCount(project.pageOrder.length)}  ·  $timestamp';
    final isBook = project.type == ProjectType.book;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.homeCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Checkbox(
                        key: ValueKey('projectSelected-${project.id}'),
                        value: selected,
                        onChanged: (_) => onTap(),
                      ),
                    ),
                  ProjectThumbnail(path: thumbnailPath, type: project.type),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: AppTheme.homeText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: AppTheme.homeMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ProjectTypeBadge(
                    label: isBook ? l10n.modeBook : l10n.modeDocument,
                    book: isBook,
                  ),
                  if (!selectionMode && _trashed) ...[
                    IconButton(
                      key: const ValueKey('projectRestoreButton'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: l10n.restoreAction,
                      icon: const Icon(
                        LucideIcons.rotateCcw,
                        color: AppTheme.accentDeep,
                        size: 16,
                      ),
                      onPressed: onRestore,
                    ),
                    IconButton(
                      key: const ValueKey('projectDeleteForeverButton'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: l10n.deleteForeverAction,
                      icon: const Icon(
                        LucideIcons.trash2,
                        color: Color(0xFFE05353),
                        size: 16,
                      ),
                      onPressed: () => _confirmDeleteForever(context, l10n),
                    ),
                  ] else if (!selectionMode) ...[
                    IconButton(
                      key: const ValueKey('projectFavoriteButton'),
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.transparent,
                      ),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: Icon(
                        LucideIcons.star,
                        color: project.isFavorite
                            ? const Color(0xFFFFC107)
                            : AppTheme.homeMuted,
                        size: 16,
                      ),
                      onPressed: onFavoriteToggle,
                    ),
                    PopupMenuButton<ProjectRowAction>(
                      key: const ValueKey('projectRowMenu'),
                      tooltip: l10n.projectRowMenu,
                      color: AppTheme.homeCard,
                      style: IconButton.styleFrom(
                        shape: const CircleBorder(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: Colors.transparent,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case ProjectRowAction.share:
                            onShare?.call();
                          case ProjectRowAction.rename:
                            onRename?.call();
                          case ProjectRowAction.moveToFolder:
                            onMoveToFolder?.call();
                          case ProjectRowAction.editTags:
                            onEditTags?.call();
                          case ProjectRowAction.delete:
                            onDelete!();
                          case ProjectRowAction.recognizeText:
                        }
                      },
                      itemBuilder: (context) => [
                        if (onShare != null)
                          PopupMenuItem(
                            value: ProjectRowAction.share,
                            child: Text(l10n.share),
                          ),
                        if (onRename != null)
                          PopupMenuItem(
                            value: ProjectRowAction.rename,
                            child: Text(l10n.rename),
                          ),
                        if (onMoveToFolder != null)
                          PopupMenuItem(
                            value: ProjectRowAction.moveToFolder,
                            child: Text(l10n.moveToFolder),
                          ),
                        if (onEditTags != null)
                          PopupMenuItem(
                            value: ProjectRowAction.editTags,
                            child: Text(l10n.editTags),
                          ),
                        PopupMenuItem(
                          value: ProjectRowAction.recognizeText,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteForever(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteForeverConfirmTitle),
        content: Text(l10n.deleteForeverConfirmBody(project.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.deleteForeverAction,
              style: const TextStyle(color: Color(0xFFE05353)),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onDeleteForever!();
  }
}

class ProjectTypeBadge extends StatelessWidget {
  const ProjectTypeBadge({super.key, required this.label, required this.book});

  final String label;
  final bool book;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: book ? const Color(0x3322A8FF) : const Color(0x333DFF8A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          color: book ? const Color(0xFF8FD0FF) : AppTheme.accent,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ProjectThumbnail extends StatelessWidget {
  const ProjectThumbnail({
    super.key,
    required this.path,
    required this.type,
    this.width = 40,
    this.height = 48,
    this.iconSize = 16,
  });

  final String? path;
  final ProjectType type;
  final double width;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppTheme.homeIconWell,
      child: Center(
        child: Icon(
          type == ProjectType.book
              ? LucideIcons.bookOpen
              : LucideIcons.fileText,
          color: AppTheme.accent,
          size: iconSize,
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: path == null
            ? fallback
            : PageImage(
                path: path!,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
}

/// Shared empty state for the Favorites and Trash pages.
class ProjectListEmptyState extends StatelessWidget {
  const ProjectListEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.homeCard,
                shape: BoxShape.circle,
                boxShadow: AppTheme.cardShadow,
              ),
              child: Icon(icon, color: AppTheme.accent, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.homeText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppTheme.homeMuted,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
