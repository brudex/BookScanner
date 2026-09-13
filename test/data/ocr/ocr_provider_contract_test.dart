import 'package:bookscanner/data/services/ocr/adapters/fake_ocr_provider.dart';
import 'package:bookscanner/domain/providers/ocr_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract test (SPEC 9.7): asserts the behavior every [OcrProvider]
/// adapter must satisfy, independent of which concrete implementation is
/// under test. Currently exercised against [FakeOcrProvider]; the same
/// suite should be pointed at the native Android/iOS adapters once they can
/// run in an instrumented/simulator environment (tracked in
/// IMPLEMENTATION_STATUS.md).
void runOcrProviderContractTests(String label, OcrProvider Function() build) {
  group('OcrProvider contract ($label)', () {
    test('supportedLanguages returns a non-empty set', () async {
      final provider = build();
      final languages = await provider.supportedLanguages();
      expect(languages, isNotEmpty);
    });

    test(
      'recognize returns raw blocks with unknown type and provider order',
      () async {
        final provider = build();
        final result = await provider.recognize(
          const OcrRequest(
            imagePath: '/tmp/does-not-matter.jpg',
            languages: ['en'],
          ),
        );

        expect(result.blocks, isNotEmpty);
        expect(result.providerInfo.providerName, isNotEmpty);
        for (var i = 0; i < result.blocks.length; i++) {
          final block = result.blocks[i];
          expect(block.blockType.name, 'unknown');
          expect(block.readingOrder, i);
          expect(block.text, isNotEmpty);
          expect(block.confidence, inInclusiveRange(0.0, 1.0));
          expect(block.boundingPolygon.points, isNotEmpty);
        }
      },
    );

    test(
      'requiresNetwork is a stable boolean (on-device adapters must be false)',
      () async {
        final provider = build();
        expect(provider.requiresNetwork, isFalse);
      },
    );
  });
}

void main() {
  runOcrProviderContractTests('fake', FakeOcrProvider.new);
}
