import 'package:bookscanner/data/services/scanner/adapters/cunning_document_scanner_capture_provider.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'books use ML Kit Base mode (no Enhance step that washes pages out)',
    () {
      expect(
        CunningDocumentScannerCaptureProvider.androidModeFor(
          CaptureMode.bookSpread,
        ),
        AndroidScannerMode.base,
      );
    },
  );

  test('documents and IDs keep ML Kit Full mode', () {
    for (final mode in [CaptureMode.singlePage, CaptureMode.idCard, null]) {
      expect(
        CunningDocumentScannerCaptureProvider.androidModeFor(mode),
        AndroidScannerMode.full,
        reason: '$mode',
      );
    }
  });
}
