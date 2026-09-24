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
