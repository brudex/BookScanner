import 'package:bookscanner/main.dart';
import 'package:bookscanner/ui/core/di/service_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// SPEC 13: "Integration tests must cover: first launch/permissions,
/// document capture with a fake adapter, ...". This first slice covers the
/// first-launch → new-scan → capture-permission-flow path, which is
/// identical on Android and iOS since it only exercises Flutter-side
/// routing, DI, and the local database — no platform-specific capture
/// behavior yet. Run on both an Android emulator/device and an iOS
/// simulator/device (SPEC 13: "Run integration tests on at least one
/// physical or virtual Android target and one iOS simulator/device").
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupServiceLocator();
  });

  testWidgets(
    'first launch shows empty library, New Scan creates a project and opens Capture',
    (tester) async {
      await tester.pumpWidget(const BookScannerApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('libraryTitle')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('newScanFab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('newScanModeDocument')), findsOneWidget);
      expect(find.byKey(const ValueKey('newScanModeBook')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('newScanModeDocument')));
      await tester.pumpAndSettle();

      // Capture screen loaded: either the permission rationale (denied) or
      // the live preview (granted) must appear — either way, the app must
      // not crash and must not stay on a bare loading spinner forever.
      final sawPermissionAction = find.byKey(
        const ValueKey('capturePermissionAction'),
      );
      final sawShutter = find.byKey(const ValueKey('shutterButton'));
      expect(
        sawPermissionAction.evaluate().isNotEmpty ||
            sawShutter.evaluate().isNotEmpty,
        isTrue,
        reason:
            'Capture screen should reach either the permission-rationale or the live-preview state',
      );

      if (sawShutter.evaluate().isNotEmpty) {
        // Permission already granted (e.g. a prior manual test run on this
        // emulator/simulator granted it): exercise the real "Done" -> close
        // session -> navigate-to-review path. This is the exact path that
        // previously threw a spurious ProviderException from
        // NativeCaptureProvider.closeSession on every successful void
        // platform-channel call and silently aborted the navigation.
        await tester.tap(find.byKey(const ValueKey('captureDoneButton')));
        await tester.pumpAndSettle();
        // "Done" now prompts to name the scan (defaulted to a timestamp)
        // before navigating -- accept the default rather than typing a name.
        await tester.tap(find.byKey(const ValueKey('captureNameSaveButton')));
        await tester.pumpAndSettle();
        // Present on the Review screen regardless of page count (0 pages
        // shows a text placeholder instead of `pageReviewList`), so this
        // confirms navigation away from Capture actually happened.
        expect(
          find.byKey(const ValueKey('reviewAddPageButton')),
          findsOneWidget,
        );
      }
    },
  );
}
