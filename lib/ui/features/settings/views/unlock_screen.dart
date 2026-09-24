import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/app_lock_controller.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';

/// Shown instead of Library when [AppSettings.appLockEnabled] is on and the
/// app hasn't been unlocked yet this launch (SPEC 6.9), gated behind the
/// router's redirect and re-armed on resume by the lifecycle observer in
/// `main.dart`.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, this.localAuth, this.appLockController});

  /// Injectable for widget tests; production code leaves these null and
  /// gets real instances wired through the composition root.
  final LocalAuthentication? localAuth;
  final AppLockController? appLockController;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  late final LocalAuthentication _localAuth;
  late final AppLockController _appLockController;
  bool _authenticating = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _localAuth = widget.localAuth ?? LocalAuthentication();
    _appLockController = widget.appLockController ?? locator<AppLockController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _failed = false;
    });
    var authenticated = false;
    try {
      authenticated = await _localAuth.authenticate(
        localizedReason: AppLocalizations.of(context).unlockSubtitle,
      );
    } on Exception {
      authenticated = false;
    }
    if (!mounted) return;
    if (authenticated) {
      _appLockController.unlock();
      context.go(AppRoutes.library);
      return;
    }
    setState(() {
      _authenticating = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Theme(
      data: AppTheme.light(),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.homeGradient),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppTheme.homeIconWell,
                        shape: BoxShape.circle,
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: const Icon(
                        LucideIcons.lock,
                        size: 40,
                        color: AppTheme.accentDeep,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.unlockTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.homeText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.unlockSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: AppTheme.homeMuted,
                        fontSize: 14,
                      ),
                    ),
                    if (_failed) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.unlockFailed,
                        key: const ValueKey('unlockFailedText'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: Color(0xFFE05353),
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        key: const ValueKey('unlockButton'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        onPressed: _authenticating ? null : _unlock,
                        child: _authenticating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                l10n.unlockButton,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
