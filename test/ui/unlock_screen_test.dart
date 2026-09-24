import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/routing/app_router.dart';
import 'package:bookscanner/ui/core/app_lock_controller.dart';
import 'package:bookscanner/ui/features/settings/views/unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

import 'fakes/fake_local_auth_platform.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

/// A minimal real `GoRouter` (library + unlock only) so `context.go(...)` on
/// a successful unlock has somewhere to navigate to, instead of throwing for
/// lack of a router ancestor.
Widget _wrapWithRouter(AppLockController appLockController) {
  final router = GoRouter(
    initialLocation: AppRoutes.unlock,
    routes: [
      GoRoute(
        path: AppRoutes.library,
        builder: (context, state) =>
            const Scaffold(body: Text('Library', key: ValueKey('library'))),
      ),
      GoRoute(
        path: AppRoutes.unlock,
        builder: (context, state) => UnlockScreen(
          localAuth: LocalAuthentication(),
          appLockController: appLockController,
        ),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

void main() {
  late FakeLocalAuthPlatform fakeLocalAuth;

  setUp(() {
    fakeLocalAuth = FakeLocalAuthPlatform();
    LocalAuthPlatform.instance = fakeLocalAuth;
  });

  testWidgets('auto-attempts unlock on load and navigates on success', (
    tester,
  ) async {
    fakeLocalAuth.authenticateResult = true;
    final appLockController = AppLockController();
    await tester.pumpWidget(_wrapWithRouter(appLockController));
    await tester.pumpAndSettle();

    expect(fakeLocalAuth.authenticateCalls, 1);
    expect(appLockController.unlockedThisSession, isTrue);
    expect(find.byKey(const ValueKey('library')), findsOneWidget);
  });

  testWidgets(
    'auto-attempts unlock on load and shows a retry state on failure',
    (tester) async {
      fakeLocalAuth.authenticateResult = false;
      final appLockController = AppLockController();
      await tester.pumpWidget(
        _wrap(
          UnlockScreen(
            localAuth: LocalAuthentication(),
            appLockController: appLockController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BookScanner is locked'), findsOneWidget);
      expect(find.byKey(const ValueKey('unlockFailedText')), findsOneWidget);
      expect(appLockController.unlockedThisSession, isFalse);

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('unlockButton')),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets('tapping Unlock retries and can then succeed', (tester) async {
    fakeLocalAuth.authenticateResult = false;
    final appLockController = AppLockController();
    await tester.pumpWidget(_wrapWithRouter(appLockController));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unlockFailedText')), findsOneWidget);

    fakeLocalAuth.authenticateResult = true;
    await tester.tap(find.byKey(const ValueKey('unlockButton')));
    await tester.pumpAndSettle();

    expect(appLockController.unlockedThisSession, isTrue);
    expect(find.byKey(const ValueKey('library')), findsOneWidget);
  });
}
