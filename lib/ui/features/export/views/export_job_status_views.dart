import 'package:flutter/material.dart';
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

  final ExportJob job;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: job.progress,
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
  });

  final ExportJob job;
  final AppLocalizations l10n;
  final VoidCallback onRetry;

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
          if (job.error != null) Text(job.error!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    ),
  );
}
