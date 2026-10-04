import 'package:bookscanner/ui/core/widgets/app_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(AppBackdropStyle style) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 360,
        height: 780,
        child: AppBackdrop(style: style),
      ),
    ),
  );

  testWidgets('shows the gradient at once, then the rendered artwork', (
    tester,
  ) async {
    await tester.pumpWidget(host(AppBackdropStyle.home));
    expect(find.byType(RawImage), findsNothing);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();

    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    // Rendered at half the device pixel ratio to keep memory low.
    final dpr = tester.view.devicePixelRatio;
    expect(image.width, (360 * dpr * 0.5).ceil());
  });

  testWidgets('screens of the same size share one cached image', (
    tester,
  ) async {
    await tester.pumpWidget(host(AppBackdropStyle.inner));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    final first = tester.widget<RawImage>(find.byType(RawImage)).image;

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(AppBackdropStyle.inner));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final second = tester.widget<RawImage>(find.byType(RawImage)).image;

    expect(identical(first, second), isTrue);
  });
}
