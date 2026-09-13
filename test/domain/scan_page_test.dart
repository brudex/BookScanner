import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/models/scan_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanPage buildPage({
    Set<QualityWarning> warnings = const {},
    Set<String> dismissed = const {},
  }) => ScanPage(
    id: 'p1',
    projectId: 'proj1',
    sequence: 0,
    originalImagePath: '/tmp/p1.jpg',
    status: PageStatus.ready,
    warnings: warnings,
    dismissedWarnings: dismissed,
  );

  test('needsReview is false with no warnings', () {
    expect(buildPage().needsReview, isFalse);
  });

  test('needsReview is true with an undismissed warning', () {
    final page = buildPage(warnings: {QualityWarning.blur});
    expect(page.needsReview, isTrue);
  });

  test('needsReview is false once the only warning is dismissed', () {
    final page = buildPage(
      warnings: {QualityWarning.blur},
      dismissed: {'blur'},
    );
    expect(page.needsReview, isFalse);
  });

  test('copyWith preserves unspecified fields', () {
    final page = buildPage().copyWith(rotationDegrees: 90);
    expect(page.rotationDegrees, 90);
    expect(page.id, 'p1');
    expect(page.originalImagePath, '/tmp/p1.jpg');
  });

  test('copyWith clearLogicalPageLabel removes the label', () {
    final page = buildPage().copyWith(logicalPageLabel: '12');
    expect(page.logicalPageLabel, '12');
    final cleared = page.copyWith(clearLogicalPageLabel: true);
    expect(cleared.logicalPageLabel, isNull);
  });
}
