import 'package:flutter/material.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

/// Covers a page preview while a new look is rendered or an edit is being
/// saved, so it is clear the tap registered and the user does not keep
/// tapping.
class PreviewProgressOverlay extends StatelessWidget {
  const PreviewProgressOverlay({
    super.key,
    required this.busy,
    required this.child,
    this.saving = false,
  });

  final bool busy;

  /// Shows "Saving…" instead of "Applying…" (and implies [busy]).
  final bool saving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        if (busy || saving)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                key: const ValueKey('previewApplyingOverlay'),
                color: Colors.black38,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            saving
                                ? AppLocalizations.of(context).savingChanges
                                : AppLocalizations.of(context).applyingChanges,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
