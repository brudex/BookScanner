import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/repositories/export_job_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/repositories/settings_repository.dart';
import '../../../../domain/use_cases/export_images_use_case.dart';
import '../../../../domain/use_cases/export_on_server_use_case.dart';
import '../../../../domain/use_cases/export_project_use_case.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../page_review/views/export_convert_sheet.dart';
import '../view_models/export_view_model.dart';
import 'export_job_status_views.dart';

/// Runs one export and shows its progress, then the finished file (share /
/// save) or the failure with Retry.
///
/// The format and its options are chosen on the Export / Convert sheet.
/// Review opens this screen with that choice ([launch]); entry points that
/// have no choice yet (library row menu, favorites, search, folders) get
/// the same sheet first, and dismissing it goes back. There is no separate
/// options form any more.
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.projectId,
    this.viewModel,
    this.launch,
  });

  final String projectId;

  /// Injectable for widget tests; production code leaves this null.
  final ExportViewModel? viewModel;

  /// The format and options already chosen on the Export / Convert sheet.
  final ExportLaunch? launch;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ExportViewModel _viewModel;

  /// From the moment an export is requested until its job exists (and,
  /// for local exports, until it finishes): progress is shown, never an
  /// empty or stale screen.
  bool _starting = true;

  /// Last requested format, for Retry after a failure before a job existed.
  ExportFormat? _lastFormat;

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
          settingsRepository: locator<SettingsRepository>(),
          exportImagesUseCase: locator<ExportImagesUseCase>(),
          exportOnServer: locator<ExportOnServerUseCase>(),
        );
    _viewModel.initialize().then(
      (_) {
        if (!mounted) return;
        final launch = widget.launch;
        if (launch != null) {
          unawaited(_run(launch));
        } else {
          unawaited(_chooseThenRun());
        }
      },
      onError: (Object _) {
        if (mounted) setState(() => _starting = false);
      },
    );
  }

  @override
  void dispose() {
    if (widget.viewModel == null) _viewModel.dispose();
    super.dispose();
  }

  /// No format chosen yet: show the Export / Convert sheet; dismissing it
  /// leaves this screen.
  Future<void> _chooseThenRun() async {
    final launch = await showExportConvertSheet(context);
    if (!mounted) return;
    if (launch == null) {
      _leave();
      return;
    }
    await _run(launch);
  }

  Future<void> _run(ExportLaunch launch) async {
    final pdf = launch.pdfOptions;
    if (pdf != null) _viewModel.setPdfOptions(pdf);
    final markdown = launch.markdownOptions;
    if (markdown != null) _viewModel.setMarkdownOptions(markdown);
    final epub = launch.epubOptions;
    if (epub != null) _viewModel.setEpubOptions(epub);
    await _startExport(launch.format);
  }

  Future<void> _startExport(ExportFormat format) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _starting = true;
      _lastFormat = format;
    });
    try {
      if (await _viewModel.needsLargeExportAcknowledgement()) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: Text(
              l10n.largeExportAcknowledgement(_viewModel.pageCount),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.continueToCapture),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          _leave();
          return;
        }
      }
      await _viewModel.startExport(format);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.homeShell(),
      child: Scaffold(
        backgroundColor: AppTheme.homeBackground,
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
                onRetry: () => _startExport(job.format),
              );
            }
            final lastFormat = _lastFormat;
            if (!_starting &&
                job == null &&
                _viewModel.error != null &&
                lastFormat != null) {
              // A local export that failed before a job existed used to
              // leave the user on a form with no message.
              return ExportFailedView(
                job: null,
                l10n: l10n,
                message: '${_viewModel.error}',
                onRetry: () => _startExport(lastFormat),
              );
            }
            // Preparing, or waiting for the format sheet.
            return ExportProgressView(job: null, l10n: l10n);
          },
        ),
      ),
    );
  }
}
