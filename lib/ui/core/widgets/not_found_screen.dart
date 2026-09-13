import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../routing/app_router.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 64),
              const SizedBox(height: 16),
              Text(
                error?.toString() ?? 'Page not found',
                textAlign: TextAlign.center,
                key: const ValueKey('notFoundMessage'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('notFoundGoHome'),
                onPressed: () => context.go(AppRoutes.library),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
