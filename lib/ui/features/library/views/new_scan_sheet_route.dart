import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';

/// Mode picker shown when the user taps "New Scan" (SPEC 5.1 step 1, 5.2
/// step 1). Creates the project immediately so it exists (and is
/// resumable) even if the user backgrounds the app before capturing a
/// single page.
class NewScanSheetRoute extends StatefulWidget {
  const NewScanSheetRoute({super.key});

  /// Book projects collect optional metadata first (SPEC 5.2 step 2).
  /// Documents go straight to capture.
  static String afterCreate(Project project) => project.type == ProjectType.book
      ? AppRoutes.bookSetupFor(project.id)
      : AppRoutes.captureFor(project.id);

  @override
  State<NewScanSheetRoute> createState() => _NewScanSheetRouteState();
}

class _NewScanSheetRouteState extends State<NewScanSheetRoute> {
  bool _creating = false;

  Future<void> _createAndGo(ProjectType type) async {
    if (_creating) return;
    setState(() => _creating = true);
    final repository = locator<ProjectRepository>();
    final l10n = AppLocalizations.of(context);
    final defaultTitle = type == ProjectType.book
        ? l10n.modeBook
        : l10n.modeDocument;
    final project = await repository.createProject(
      type: type,
      title: defaultTitle,
    );
    if (!mounted) return;
    context.pushReplacement(NewScanSheetRoute.afterCreate(project));
  }

  Future<void> _createIdScan() async {
    if (_creating) return;
    setState(() => _creating = true);
    final project = await locator<ProjectRepository>().createProject(
      type: ProjectType.document,
      title: AppLocalizations.of(context).modeScanId,
    );
    if (!mounted) return;
    context.pushReplacement(
      AppRoutes.captureFor(project.id),
      extra: CaptureMode.idCard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.homeShell(),
      child: Scaffold(
        backgroundColor: AppTheme.homeBackground,
        appBar: AppBar(title: Text(l10n.newScanModeTitle)),
        body: _creating
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    _ModeCard(
                      key: const ValueKey('newScanModeDocument'),
                      icon: LucideIcons.fileText,
                      title: l10n.modeDocument,
                      subtitle: l10n.modeDocumentSubtitle,
                      onTap: () => _createAndGo(ProjectType.document),
                    ),
                    const SizedBox(height: 12),
                    _ModeCard(
                      key: const ValueKey('newScanModeBook'),
                      icon: LucideIcons.bookOpen,
                      title: l10n.modeBook,
                      subtitle: l10n.modeBookSubtitle,
                      onTap: () => _createAndGo(ProjectType.book),
                    ),
                    const SizedBox(height: 12),
                    _ModeCard(
                      key: const ValueKey('newScanModeId'),
                      icon: LucideIcons.creditCard,
                      title: l10n.modeScanId,
                      subtitle: l10n.modeScanIdSubtitle,
                      onTap: _createIdScan,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
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
      color: AppTheme.homeCard,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppTheme.homeHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: AppTheme.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: AppTheme.homeText,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: AppTheme.homeMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, color: AppTheme.accent),
            ],
          ),
        ),
      ),
    );
  }
}
