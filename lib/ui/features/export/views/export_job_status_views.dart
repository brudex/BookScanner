import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Shared single-job progress/completed/failed views, used by [ExportScreen]
/// and the multi-source page-composition screen (`PageOperationsScreen`)
/// for their single-output export path. Extracted out of `export_screen.dart`
/// (formerly private `_ProgressView`/`_CompletedView`/`_FailedView`) so both
/// screens render an identical result UI without duplicating it; the
/// `ValueKey`s below are unchanged so existing widget tests keep passing.
class ExportProgressView extends StatelessWidget {
  const ExportProgressView({super.key, required this.job, required this.l10n});

  /// Null while the export is still being prepared (no job yet): the bar
  /// then runs indeterminate.
  final ExportJob? job;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: job?.progress,
            key: const ValueKey('exportProgressBar'),
          ),
          const SizedBox(height: 16),
          Text(l10n.exportInProgress),
        ],
      ),
    ),
  );
}

class ExportCompletedView extends StatelessWidget {
  const ExportCompletedView({super.key, required this.job, required this.l10n});

  final ExportJob job;
  final AppLocalizations l10n;

  bool get _isPdf =>
      job.format == ExportFormat.imagePdf ||
      job.format == ExportFormat.searchablePdf;

  Future<void> _print() async {
    final path = job.outputPath;
    if (path == null || !_isPdf) return;
    final bytes = await File(path).readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _saveAs() async {
    final path = job.outputPath;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final name = p.basename(path);
    await FilePicker.saveFile(
      dialogTitle: l10n.saveAsAction,
      fileName: name,
      bytes: bytes,
    );
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 56),
          const SizedBox(height: 16),
          Text(
            l10n.exportComplete,
            key: const ValueKey('exportCompleteMessage'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('exportShareButton'),
            onPressed: () {
              final path = job.outputPath;
              if (path != null) {
                SharePlus.instance.share(ShareParams(files: [XFile(path)]));
              }
            },
            icon: const Icon(Icons.share_outlined),
            label: Text(l10n.share),
          ),
          if (_isPdf) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('exportPrintButton'),
              onPressed: _print,
              icon: const Icon(Icons.print_outlined),
              label: Text(l10n.printAction),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            key: const ValueKey('exportSaveAsButton'),
            onPressed: _saveAs,
            icon: const Icon(Icons.save_alt_outlined),
            label: Text(l10n.saveAsAction),
          ),
        ],
      ),
    ),
  );
}

class ExportFailedView extends StatelessWidget {
  const ExportFailedView({
    super.key,
    required this.job,
    required this.l10n,
    required this.onRetry,
    this.message,
  });

  /// Null when the export failed before a job was created; the error is
  /// then given in [message].
  final ExportJob? job;
  final AppLocalizations l10n;
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 16),
          Text(l10n.exportFailed),
          if ((job?.error ?? message) != null)
            Text(job?.error ?? message!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    ),
  );
}
