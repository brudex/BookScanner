import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain/repositories/settings_repository.dart';
import 'l10n/gen/app_localizations.dart';
import 'routing/app_router.dart';
import 'ui/core/app_lock_controller.dart';
import 'ui/core/di/service_locator.dart';
import 'ui/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupServiceLocator();
  runApp(const BookScannerApp());
}

class BookScannerApp extends StatefulWidget {
  const BookScannerApp({super.key});

  @override
  State<BookScannerApp> createState() => _BookScannerAppState();
}

/// Re-locks the app (SPEC 6.9's app-lock setting) on background/resume, not
/// just cold start -- the router's redirect alone only fires when
/// navigating *to* Library, which never happens on a bare resume if the
/// user was already sitting on it when the app was backgrounded.
class _BookScannerAppState extends State<BookScannerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        locator<AppLockController>().lock();
      case AppLifecycleState.resumed:
        unawaited(_relockIfNeeded());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _relockIfNeeded() async {
    final settings = await locator<SettingsRepository>().getSettings();
    if (settings.appLockEnabled &&
        !locator<AppLockController>().unlockedThisSession) {
      appRouter.go(AppRoutes.unlock);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BookScanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
