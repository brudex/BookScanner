import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';

/// Mode picker shown when the user taps "New Scan" (SPEC 5.1 step 1, 5.2
/// step 1). Creates the project immediately so it exists (and is
/// resumable) even if the user backgrounds the app before capturing a
/// single page.
class NewScanSheetRoute extends StatefulWidget {
  const NewScanSheetRoute({super.key});

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
    // `pushReplacement`, not `go`: `go` replaces the whole route stack, which
    // stripped Library out of the back stack entirely -- there was no way
    // back to the project list from Capture/Review afterward. This mode
    // picker's job is done once a project exists, so it's the right screen
    // to replace; Library underneath stays intact.
    context.pushReplacement(AppRoutes.captureFor(project.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.newScanModeTitle)),
      body: _creating
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ModeCard(
                    key: const ValueKey('newScanModeDocument'),
                    icon: Icons.description_outlined,
                    title: l10n.modeDocument,
                    subtitle: l10n.modeDocumentSubtitle,
                    onTap: () => _createAndGo(ProjectType.document),
                  ),
                  const SizedBox(height: 16),
                  _ModeCard(
                    key: const ValueKey('newScanModeBook'),
                    icon: Icons.menu_book_outlined,
                    title: l10n.modeBook,
                    subtitle: l10n.modeBookSubtitle,
                    onTap: () => _createAndGo(ProjectType.book),
                  ),
                ],
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
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icon, size: 36),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}
