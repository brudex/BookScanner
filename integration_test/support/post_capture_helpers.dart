import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tap order after Continue: crop → Next → filters → Save/Next.
Future<void> completePostCaptureCrop(WidgetTester tester) async {
  final next = find.byKey(const ValueKey('cropNextButton'));
  await tester.pumpAndSettle();
  if (next.evaluate().isEmpty) return;
  await tester.tap(next);
  await tester.pumpAndSettle();
}

/// Crop (if open) → filter Save/Next for the current page.
Future<void> advancePostCapturePage(WidgetTester tester) async {
  await completePostCaptureCrop(tester);
  await tester.tap(find.byKey(const ValueKey('postCaptureSaveButton')));
  await tester.pumpAndSettle();
}

/// Picks [formatCardKey] on Review's Export / Convert sheet and confirms.
/// [searchablePdf] turns the sheet's OCR switch on (it starts off, which
/// gives an image-only PDF).
Future<void> exportFromReviewSheet(
  WidgetTester tester,
  String formatCardKey, {
  bool searchablePdf = false,
}) async {
  await tester.tap(find.byKey(const ValueKey('reviewExportButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(formatCardKey)));
  await tester.pumpAndSettle();
  if (searchablePdf) {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('reviewExportOcrSwitch')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(const ValueKey('reviewExportConfirm')));
  await tester.tap(find.byKey(const ValueKey('reviewExportConfirm')));
  await tester.pumpAndSettle();
}
