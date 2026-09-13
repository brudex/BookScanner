import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/repositories/export_job_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/export_project_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/export_view_model.dart';
import 'export_job_status_views.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.projectId, this.viewModel});

  final String projectId;

  /// Injectable for widget tests; production code leaves this null.
  final ExportViewModel? viewModel;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ExportViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        ExportViewModel(
          projectId: widget.projectId,
          projectRepository: locator<ProjectRepository>(),
          exportJobRepository: locator<ExportJobRepository>(),
          exportProjectUseCase: locator<ExportProjectUseCase>(),
        );
    _viewModel.initialize();
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.exportTitle),
        actions: [
          IconButton(
            key: const ValueKey('exportComposeButton'),
            icon: const Icon(Icons.auto_awesome_mosaic_outlined),
            tooltip: l10n.composeDocumentAction,
            onPressed: () =>
                context.push(AppRoutes.pageOperationsFor(widget.projectId)),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          final job = _viewModel.job;
          if (job != null && job.status == ExportJobStatus.running) {
            return ExportProgressView(job: job, l10n: l10n);
          }
          if (job != null && job.status == ExportJobStatus.completed) {
            return ExportCompletedView(job: job, l10n: l10n);
          }
          if (job != null && job.status == ExportJobStatus.failed) {
            return ExportFailedView(
              job: job,
              l10n: l10n,
              onRetry: () => _viewModel.startExport(job.format),
            );
          }
          return _FormatPicker(onSelected: _viewModel.startExport, l10n: l10n);
        },
      ),
    );
  }
}

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({required this.onSelected, required this.l10n});

  final ValueChanged<ExportFormat> onSelected;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _FormatTile(
          key: const ValueKey('exportFormatImagePdf'),
          icon: Icons.picture_as_pdf_outlined,
          label: l10n.exportImagePdf,
          onTap: () => onSelected(ExportFormat.imagePdf),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatSearchablePdf'),
          icon: Icons.picture_as_pdf,
          label: l10n.exportSearchablePdf,
          onTap: () => onSelected(ExportFormat.searchablePdf),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatMarkdown'),
          icon: Icons.description_outlined,
          label: l10n.exportMarkdown,
          onTap: () => onSelected(ExportFormat.markdown),
        ),
        _FormatTile(
          key: const ValueKey('exportFormatDocx'),
          icon: Icons.article_outlined,
          label: l10n.exportDocx,
          onTap: () => onSelected(ExportFormat.docx),
        ),
      ],
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(leading: Icon(icon), title: Text(label), onTap: onTap),
  );
}
