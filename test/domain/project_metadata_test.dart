import 'package:bookscanner/domain/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson defaults a missing bookScanMode to one page per shot', () {
    final metadata = ProjectMetadata.fromJson(const {'language': 'en'});
    expect(metadata.bookScanMode, BookScanMode.singlePage);
    expect(metadata.startingPageNumber, 1);
    expect(metadata.pageOrderDirection, PageOrderDirection.leftToRight);
  });

  test('toJson/fromJson round-trips book scan mode', () {
    const original = ProjectMetadata(
      author: 'Ada',
      language: 'fr',
      startingPageNumber: 12,
      pageOrderDirection: PageOrderDirection.rightToLeft,
      bookScanMode: BookScanMode.singlePage,
    );
    final restored = ProjectMetadata.fromJson(original.toJson());
    expect(restored.author, 'Ada');
    expect(restored.language, 'fr');
    expect(restored.startingPageNumber, 12);
    expect(restored.pageOrderDirection, PageOrderDirection.rightToLeft);
    expect(restored.bookScanMode, BookScanMode.singlePage);
  });
}
