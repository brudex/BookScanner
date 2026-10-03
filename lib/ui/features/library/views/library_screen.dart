import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/folder_repository.dart';
import '../../../../domain/repositories/page_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/models/scan_page.dart';
import '../../../../domain/use_cases/import_pages_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/discard_unsaved_capture.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/text_input_dialog.dart';
import '../view_models/library_view_model.dart';
import 'project_list_row.dart';

enum _LibraryTypeFilter { all, document, book }

enum _LibraryViewMode { list, grid }

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
  bool _importing = false;
  _LibraryTypeFilter _typeFilter = _LibraryTypeFilter.all;
  _LibraryViewMode _viewMode = _LibraryViewMode.list;
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
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  Future<Project> _createProject(ProjectType type) {
    final l10n = AppLocalizations.of(context);
    return locator<ProjectRepository>().createProject(
      type: type,
      title: type == ProjectType.book ? l10n.modeBook : l10n.modeDocument,
    );
  }

  Future<void> _startDocumentScan() async {
    final project = await _createProject(ProjectType.document);
    if (!mounted) return;
    context.push(AppRoutes.captureFor(project.id));
  }

  Future<void> _startIdScan() async {
    final project = await locator<ProjectRepository>().createProject(
      type: ProjectType.document,
      title: AppLocalizations.of(context).modeScanId,
    );
    if (!mounted) return;
    context.push(AppRoutes.captureFor(project.id), extra: CaptureMode.idCard);
  }

  Future<void> _startBookScan() async {
    final project = await _createProject(ProjectType.book);
    if (!mounted) return;
    context.push(AppRoutes.bookSetupFor(project.id));
  }

  Future<void> _createFolderFromHome() async {
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
    await locator<FolderRepository>().createFolder(trimmed);
    if (!mounted) return;
    context.push(AppRoutes.folders);
  }

  Future<void> _importGallery() async {
    if (_importing) return;
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    await _importIntoNewDocument(
      (useCase, projectId) => useCase.importImages(
        [for (final f in files) f.path],
        projectId: projectId,
        startSequence: 0,
      ),
    );
  }

  Future<void> _importPdf() async {
    if (_importing) return;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _importIntoNewDocument(
      (useCase, projectId) =>
          useCase.importPdf(path, projectId: projectId, startSequence: 0),
    );
  }

  /// Creates a document, runs [import] into it and opens Review. On failure
  /// or when nothing was imported, the new document is removed (no empty
  /// project in the library) and the user is told instead of nothing
  /// happening.
  Future<void> _importIntoNewDocument(
    Future<List<ScanPage>> Function(ImportPagesUseCase useCase, String id)
    import,
  ) async {
    setState(() => _importing = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Project? project;
    var imported = <ScanPage>[];
    try {
      project = await _createProject(ProjectType.document);
      imported = await import(locator<ImportPagesUseCase>(), project.id);
    } on Object {
      imported = const [];
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (project == null) return;
    if (imported.isEmpty) {
      try {
        await discardUnsavedCapture(project.id);
      } on Object {
        // Best effort: an empty project is harmless.
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.importFailed)));
      return;
    }
    if (!mounted) return;
    context.push(AppRoutes.pageReviewFor(project.id));
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

  List<Project> _visibleProjects() {
    final projects = _viewModel.projects;
    return switch (_typeFilter) {
      _LibraryTypeFilter.all => projects,
      _LibraryTypeFilter.document =>
        projects.where((p) => p.type == ProjectType.document).toList(),
      _LibraryTypeFilter.book =>
        projects.where((p) => p.type == ProjectType.book).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: AppTheme.homeBackground,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Theme(
        data: AppTheme.homeShell(),
        child: Stack(
          children: [
            const Positioned.fill(child: _HomeAmbientBackground()),
            Scaffold(
              backgroundColor: Colors.transparent,
              extendBody: true,
              floatingActionButton: _selectedIds.isEmpty
                  ? _ScanFab(
                      key: const ValueKey('newScanFab'),
                      tooltip: l10n.homeNavScan,
                      onPressed: () => context.push(AppRoutes.newScan),
                    )
                  : null,
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerDocked,
              body: Stack(
                children: [
                  ListenableBuilder(
                    listenable: _viewModel,
                    builder: (context, _) => _buildBody(context, l10n),
                  ),
                  if (_importing)
                    ColoredBox(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(
                        child: CircularProgressIndicator(
                          key: ValueKey('homeImporting'),
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                ],
              ),
              bottomNavigationBar: _selectedIds.isEmpty
                  ? _HomeDock(
                      l10n: l10n,
                      onHome: () {},
                      onScans: () => context.push(AppRoutes.scansSearch),
                    )
                  : _SelectionActionBar(
                      l10n: l10n,
                      count: _selectedIds.length,
                      onCancel: () => setState(_selectedIds.clear),
                      onFavorite: _bulkFavorite,
                      onRename: _batchRename,
                      onDelete: _bulkDelete,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_viewModel.loading && _viewModel.projects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null) {
      return Center(child: Text('${_viewModel.error}'));
    }

    final visible = _visibleProjects();
    return CustomScrollView(
      key: const ValueKey('libraryScroll'),
      slivers: [
        SliverToBoxAdapter(child: _HomeHeader(l10n: l10n)),
        SliverToBoxAdapter(
          child: _QuickStartRow(
            l10n: l10n,
            onDocumentScan: _startDocumentScan,
            onBookScan: _startBookScan,
            onIdScan: _startIdScan,
          ),
        ),
        SliverToBoxAdapter(
          child: _HubGrid(
            l10n: l10n,
            onScan: _startDocumentScan,
            onScanId: _startIdScan,
            onBook: _startBookScan,
            onGallery: _importGallery,
            onImport: _importPdf,
            onAddFolder: _createFolderFromHome,
          ),
        ),
        SliverToBoxAdapter(
          child: _RecentsHeader(
            l10n: l10n,
            count: visible.length,
            filter: _typeFilter,
            onFilter: (filter) => setState(() => _typeFilter = filter),
            sortField: _viewModel.sortField,
            descending: _viewModel.descending,
            onSort: _viewModel.setSortOrder,
            viewMode: _viewMode,
            onToggleView: () => setState(
              () => _viewMode = _viewMode == _LibraryViewMode.list
                  ? _LibraryViewMode.grid
                  : _LibraryViewMode.list,
            ),
          ),
        ),
        if (_viewModel.projects.isEmpty)
          SliverToBoxAdapter(child: _EmptyLibrary(l10n: l10n))
        else if (_viewMode == _LibraryViewMode.grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverGrid(
              key: const ValueKey('libraryGrid'),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildListDelegate([
                for (final project in visible)
                  _selectableRow(
                    project,
                    _ProjectGridTile(
                      key: ValueKey('project-${project.id}'),
                      project: project,
                      thumbnailPath: _viewModel.thumbnailFor(project.id),
                      selected: _selectedIds.contains(project.id),
                      onTap: () => _selectedIds.isNotEmpty
                          ? _toggleSelected(project.id)
                          : context.push(AppRoutes.pageReviewFor(project.id)),
                      onLongPress: () => _toggleSelected(project.id),
                    ),
                  ),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 12),
            sliver: SliverList(
              key: const ValueKey('libraryList'),
              delegate: SliverChildListDelegate([
                for (final project in visible)
                  _selectableRow(
                    project,
                    ProjectListRow(
                      key: ValueKey('project-${project.id}'),
                      project: project,
                      thumbnailPath: _viewModel.thumbnailFor(project.id),
                      onTap: () => _selectedIds.isNotEmpty
                          ? _toggleSelected(project.id)
                          : context.push(AppRoutes.pageReviewFor(project.id)),
                      onFavoriteToggle: () =>
                          _viewModel.toggleFavorite(project),
                      onDelete: () => _viewModel.moveToTrash(project),
                      onShare: () =>
                          context.push(AppRoutes.exportFor(project.id)),
                      onRename: () => _renameProject(project),
                      onLongPress: () => _toggleSelected(project.id),
                      onMoveToFolder: () => _moveToFolder(project),
                      onEditTags: () => _editTags(project),
                    ),
                  ),
              ]),
            ),
          ),
        // `extendBody: true` lets this scroll view's content render behind
        // the floating `_HomeDock`/`_SelectionActionBar`, so without this
        // the last row(s) end up visually covered by it once scrolled to
        // the bottom. Sized to clear the dock's own rendered height (icon +
        // label + its internal padding) plus its SafeArea margins and the
        // device's own bottom safe-area inset, not just a fixed guess.
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.of(context).padding.bottom + 110),
        ),
      ],
    );
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  /// Overlays a selection checkbox on [child] once selection mode is active
  /// (any project selected), without changing `child`'s own tap/long-press
  /// handling -- those are wired by the caller to toggle selection too.
  Widget _selectableRow(Project project, Widget child) {
    if (_selectedIds.isEmpty) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 4,
          left: 24,
          child: IgnorePointer(
            child: Checkbox(
              value: _selectedIds.contains(project.id),
              onChanged: (_) {},
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _moveToFolder(Project project) async {
    final l10n = AppLocalizations.of(context);
    final folderRepository = locator<FolderRepository>();
    final folders = await folderRepository.watchFolders().first;
    if (!mounted) return;
    final selectedFolderId = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('moveToFolderNone'),
              leading: const Icon(LucideIcons.x),
              title: Text(l10n.noFolder),
              onTap: () => Navigator.of(sheetContext).pop<String?>(null),
            ),
            for (final folder in folders)
              ListTile(
                key: ValueKey('moveToFolder-${folder.id}'),
                leading: const Icon(LucideIcons.folder),
                title: Text(folder.name),
                onTap: () => Navigator.of(sheetContext).pop(folder.id),
              ),
          ],
        ),
      ),
    );
    if (selectedFolderId == null && folders.isEmpty) return;
    await _viewModel.moveToFolder(project, selectedFolderId);
  }

  Future<void> _editTags(Project project) async {
    final l10n = AppLocalizations.of(context);
    final result = await showTextInputDialog(
      context: context,
      title: l10n.editTags,
      label: l10n.tagsFieldLabel,
      initialText: project.metadata.tags.join(', '),
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    );
    if (result == null) return;
    final tags = result
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    await _viewModel.updateTags(project, tags);
  }

  Future<void> _batchRename() async {
    final l10n = AppLocalizations.of(context);
    final pattern = await showTextInputDialog(
      context: context,
      title: l10n.batchRename,
      label: l10n.batchRenamePatternLabel,
      initialText: '#',
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    );
    final trimmedPattern = pattern?.trim();
    if (trimmedPattern == null || trimmedPattern.isEmpty || !mounted) return;
    final projects = _viewModel.projects
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    for (var i = 0; i < projects.length; i++) {
      final name = trimmedPattern.replaceAll('#', '${i + 1}');
      await _viewModel.renameProject(projects[i], name);
    }
    setState(_selectedIds.clear);
  }

  Future<void> _bulkDelete() async {
    final projects = _viewModel.projects
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    for (final project in projects) {
      await _viewModel.moveToTrash(project);
    }
    setState(_selectedIds.clear);
  }

  Future<void> _bulkFavorite() async {
    final projects = _viewModel.projects
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    for (final project in projects) {
      if (!project.isFavorite) await _viewModel.toggleFavorite(project);
    }
    setState(_selectedIds.clear);
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            _RoundHeaderButton(
              key: const ValueKey('librarySearchButton'),
              icon: LucideIcons.search,
              tooltip: l10n.searchHint,
              onPressed: () => context.push(AppRoutes.scansSearch),
            ),
            const Spacer(),
            _RoundHeaderButton(
              key: const ValueKey('libraryFavoritesButton'),
              icon: LucideIcons.star,
              tooltip: l10n.favorites,
              onPressed: () => context.push(AppRoutes.favorites),
            ),
            const SizedBox(width: 8),
            _RoundHeaderButton(
              key: const ValueKey('libraryFoldersButton'),
              icon: LucideIcons.folder,
              tooltip: l10n.folders,
              onPressed: () => context.push(AppRoutes.folders),
            ),
            const SizedBox(width: 8),
            _RoundHeaderButton(
              key: const ValueKey('libraryTrashButton'),
              icon: LucideIcons.trash2,
              tooltip: l10n.trash,
              onPressed: () => context.push(AppRoutes.trash),
            ),
            const SizedBox(width: 8),
            _RoundHeaderButton(
              key: const ValueKey('librarySettingsButton'),
              icon: LucideIcons.settings,
              tooltip: l10n.settingsTitle,
              onPressed: () => context.push(AppRoutes.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundHeaderButton extends StatelessWidget {
  const _RoundHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Material(
          color: AppTheme.homeCard,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: const CircleBorder(
            side: BorderSide(color: AppTheme.homeHairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(icon, color: AppTheme.homeIcon, size: 18),
          ),
        ),
      ),
    );
  }
}

class _HomeAmbientBackground extends StatelessWidget {
  const _HomeAmbientBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppTheme.homeGradient),
      child: CustomPaint(painter: _HomeGlowPainter()),
    );
  }
}

class _HomeGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final top = Paint()
      ..shader =
          RadialGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0.28),
              AppTheme.accent.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.85, size.height * 0.08),
              radius: size.width * 0.55,
            ),
          );
    canvas.drawRect(Offset.zero & size, top);

    final mid = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF1DBF5A).withValues(alpha: 0.22),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.1, size.height * 0.45),
              radius: size.width * 0.7,
            ),
          );
    canvas.drawRect(Offset.zero & size, mid);

    final bottom = Paint()
      ..shader =
          RadialGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0.18),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.6, size.height * 0.92),
              radius: size.width * 0.65,
            ),
          );
    canvas.drawRect(Offset.zero & size, bottom);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.l10n,
    required this.onDocumentScan,
    required this.onBookScan,
    required this.onIdScan,
  });

  final AppLocalizations l10n;
  final VoidCallback onDocumentScan;
  final VoidCallback onBookScan;
  final VoidCallback onIdScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 168,
        child: Row(
          children: [
            Expanded(
              child: _HeroScanCard(
                key: const ValueKey('homeActionDocumentScan'),
                icon: LucideIcons.files,
                title: l10n.homeActionDocumentScan,
                subtitle: l10n.homeActionDocumentScanSubtitle,
                onTap: onDocumentScan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroScanCard(
                key: const ValueKey('homeActionBookScan'),
                icon: LucideIcons.bookOpen,
                title: l10n.homeActionBookScan,
                subtitle: l10n.homeActionBookScanSubtitle,
                onTap: onBookScan,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroScanCard(
                key: const ValueKey('homeActionIdScan'),
                icon: LucideIcons.creditCard,
                title: l10n.homeActionIdScan,
                subtitle: l10n.homeActionIdScanSubtitle,
                onTap: onIdScan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroScanCard extends StatelessWidget {
  const _HeroScanCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE6223B2E), Color(0xCC0E1C16)],
            ),
            border: Border.all(color: AppTheme.homeHairline),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppTheme.homeText, size: 28),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.homeText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.homeMuted,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Material(
                    color: AppTheme.accent,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: Color(0xFF04140C),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubGrid extends StatelessWidget {
  const _HubGrid({
    required this.l10n,
    required this.onScan,
    required this.onScanId,
    required this.onBook,
    required this.onGallery,
    required this.onImport,
    required this.onAddFolder,
  });

  final AppLocalizations l10n;
  final VoidCallback onScan;
  final VoidCallback onScanId;
  final VoidCallback onBook;
  final VoidCallback onGallery;
  final VoidCallback onImport;
  final VoidCallback onAddFolder;

  @override
  Widget build(BuildContext context) {
    final tools = <_QuickTool>[
      _QuickTool(
        key: const ValueKey('homeScanDoc'),
        iconAsset: 'assets/icons/tool_scan_doc.svg',
        label: l10n.homeScanDoc,
        onTap: onScan,
      ),
      _QuickTool(
        key: const ValueKey('homeScanId'),
        iconAsset: 'assets/icons/tool_scan_id.svg',
        label: l10n.homeScanId,
        onTap: onScanId,
      ),
      _QuickTool(
        key: const ValueKey('homeToolBook'),
        iconAsset: 'assets/icons/tool_scan_book.svg',
        label: l10n.homeScanBook,
        onTap: onBook,
      ),
      _QuickTool(
        key: const ValueKey('homeAddFolder'),
        iconAsset: 'assets/icons/tool_add_folder.svg',
        label: l10n.homeAddFolder,
        onTap: onAddFolder,
      ),
      _QuickTool(
        key: const ValueKey('homeGallery'),
        iconAsset: 'assets/icons/tool_gallery.svg',
        label: l10n.homeGallery,
        onTap: onGallery,
      ),
      _QuickTool(
        key: const ValueKey('homeImportFile'),
        iconAsset: 'assets/icons/tool_import.svg',
        label: l10n.homeImportFile,
        onTap: onImport,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              l10n.homePopularTools,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppTheme.homeText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView.separated(
              key: const ValueKey('homeQuickActionsList'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: tools.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final tool = tools[index];
                return _QuickToolTile(
                  key: tool.key,
                  iconAsset: tool.iconAsset,
                  label: tool.label,
                  onTap: tool.onTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTool {
  const _QuickTool({
    required this.key,
    required this.iconAsset,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final String iconAsset;
  final String label;
  final VoidCallback onTap;
}

class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.homeCard,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppTheme.homeHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 88,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  iconAsset,
                  width: 28,
                  height: 28,
                  colorFilter: const ColorFilter.mode(
                    AppTheme.accent,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.homeText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentsHeader extends StatelessWidget {
  const _RecentsHeader({
    required this.l10n,
    required this.count,
    required this.filter,
    required this.onFilter,
    required this.sortField,
    required this.descending,
    required this.onSort,
    required this.viewMode,
    required this.onToggleView,
  });

  final AppLocalizations l10n;
  final int count;
  final _LibraryTypeFilter filter;
  final ValueChanged<_LibraryTypeFilter> onFilter;
  final ProjectSortField sortField;
  final bool descending;
  final void Function(ProjectSortField field, {bool descending}) onSort;
  final _LibraryViewMode viewMode;
  final VoidCallback onToggleView;

  String _sortLabel(ProjectSortField field) => switch (field) {
    ProjectSortField.updatedAt => l10n.sortByDateUpdated,
    ProjectSortField.createdAt => l10n.sortByDateCreated,
    ProjectSortField.title => l10n.sortByTitle,
    ProjectSortField.pageCount => l10n.sortByPageCount,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.homeRecent,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: AppTheme.homeText,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                l10n.homeLibraryCount(count),
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: AppTheme.homeMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('libraryViewToggle'),
                onTap: onToggleView,
                borderRadius: BorderRadius.circular(8),
                child: Icon(
                  viewMode == _LibraryViewMode.list
                      ? LucideIcons.layoutGrid
                      : LucideIcons.list,
                  size: 16,
                  color: AppTheme.homeMuted,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ProjectSortField>(
                key: const ValueKey('librarySortMenu'),
                tooltip: l10n.sortAction,
                icon: const Icon(
                  LucideIcons.arrowUpDown,
                  size: 16,
                  color: AppTheme.homeMuted,
                ),
                onSelected: (field) => onSort(
                  field,
                  descending: field == sortField ? !descending : true,
                ),
                itemBuilder: (context) => [
                  for (final field in ProjectSortField.values)
                    PopupMenuItem(
                      value: field,
                      child: Text(
                        _sortLabel(field),
                        style: TextStyle(
                          fontWeight: field == sortField
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _FilterChip(
                key: const ValueKey('homeFilterAll'),
                label: l10n.homeFilterAll,
                selected: filter == _LibraryTypeFilter.all,
                onTap: () => onFilter(_LibraryTypeFilter.all),
              ),
              _FilterChip(
                key: const ValueKey('homeFilterDocuments'),
                label: l10n.homeStatDocuments,
                selected: filter == _LibraryTypeFilter.document,
                onTap: () => onFilter(_LibraryTypeFilter.document),
              ),
              _FilterChip(
                key: const ValueKey('homeFilterBooks'),
                label: l10n.homeStatBooks,
                selected: filter == _LibraryTypeFilter.book,
                onTap: () => onFilter(_LibraryTypeFilter.book),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.accent : AppTheme.homeCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: selected ? const Color(0xFF04140C) : AppTheme.homeMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.l10n,
    required this.count,
    required this.onCancel,
    required this.onFavorite,
    required this.onRename,
    required this.onDelete,
  });

  final AppLocalizations l10n;
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onFavorite;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.homeDock,
      elevation: 12,
      shadowColor: const Color(0x33001820),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('librarySelectionCancel'),
                  onPressed: onCancel,
                  icon: const Icon(LucideIcons.x, color: AppTheme.homeIcon),
                ),
                Expanded(
                  child: Text(
                    l10n.selectedCount(count),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      color: AppTheme.homeText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('librarySelectionFavorite'),
                  onPressed: onFavorite,
                  tooltip: l10n.homeFavoritesFilter,
                  icon: const Icon(LucideIcons.star, color: AppTheme.homeIcon),
                ),
                IconButton(
                  key: const ValueKey('librarySelectionRename'),
                  onPressed: onRename,
                  tooltip: l10n.batchRename,
                  icon: const Icon(
                    LucideIcons.pencil,
                    color: AppTheme.homeIcon,
                  ),
                ),
                IconButton(
                  key: const ValueKey('librarySelectionDelete'),
                  onPressed: onDelete,
                  tooltip: l10n.delete,
                  icon: const Icon(
                    LucideIcons.trash2,
                    color: Color(0xFFE05353),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeDock extends StatelessWidget {
  const _HomeDock({
    required this.l10n,
    required this.onHome,
    required this.onScans,
  });

  final AppLocalizations l10n;
  final VoidCallback onHome;
  final VoidCallback onScans;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 64,
      padding: EdgeInsets.zero,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: AppTheme.homeDock,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Row(
          children: [
            Expanded(
              child: _DockItem(
                icon: LucideIcons.house,
                label: l10n.homeNavHome,
                selected: true,
                onPressed: onHome,
              ),
            ),
            const SizedBox(width: 72),
            Expanded(
              child: _DockItem(
                key: const ValueKey('homeDockScans'),
                icon: LucideIcons.files,
                label: l10n.homeNavScans,
                onPressed: onScans,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFab extends StatelessWidget {
  const _ScanFab({super.key, required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: AppTheme.accentGlow,
        ),
        child: FloatingActionButton(
          onPressed: onPressed,
          elevation: 0,
          highlightElevation: 0,
          backgroundColor: AppTheme.accent,
          foregroundColor: const Color(0xFF04140C),
          shape: const CircleBorder(),
          child: const Icon(LucideIcons.plus, size: 28),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.homeMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectGridTile extends StatelessWidget {
  const _ProjectGridTile({
    super.key,
    required this.project,
    required this.thumbnailPath,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Project project;
  final String? thumbnailPath;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isBook = project.type == ProjectType.book;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.homeCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
        border: selected ? Border.all(color: AppTheme.accent, width: 2) : null,
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
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ProjectThumbnail(
                    path: thumbnailPath,
                    type: project.type,
                    width: double.infinity,
                    height: double.infinity,
                    iconSize: 28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  project.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.homeText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                ProjectTypeBadge(
                  label: isBook ? l10n.modeBook : l10n.modeDocument,
                  book: isBook,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.homeCard,
              shape: BoxShape.circle,
              boxShadow: AppTheme.cardShadow,
            ),
            child: const Center(
              child: Icon(LucideIcons.scan, color: AppTheme.accent, size: 22),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.libraryEmptyTitle,
            key: const ValueKey('libraryEmptyTitle'),
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.homeText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.libraryEmptySubtitle,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppTheme.homeMuted,
              fontSize: 12,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
