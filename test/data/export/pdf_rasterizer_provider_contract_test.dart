import 'package:bookscanner/data/services/export/adapters/fake_pdf_rasterizer_provider.dart';
import 'package:bookscanner/domain/providers/pdf_rasterizer_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract test (SPEC 9.7): asserts the behavior every [PdfRasterizerProvider]
/// adapter must satisfy, independent of which concrete implementation is
/// under test. Currently exercised against [FakePdfRasterizerProvider]; the
/// real `PrintingPdfRasterizerProvider` needs an instrumented/simulator
/// environment (tracked in IMPLEMENTATION_STATUS.md), same as
/// `NativeOcrProvider`.
void runPdfRasterizerProviderContractTests(
  String label,
  PdfRasterizerProvider Function() build,
) {
  group('PdfRasterizerProvider contract ($label)', () {
    test(
      'rasterize with pageIndices=null yields one page per source page, ascending',
      () async {
        final provider = build();
        final pages = await provider
            .rasterize('/tmp/does-not-matter.pdf', pageIndices: null)
            .toList();

        expect(pages, isNotEmpty);
        for (var i = 0; i < pages.length; i++) {
          expect(pages[i].pageIndex, i);
        }
      },
    );

    test(
      'rasterize with explicit pageIndices yields exactly the requested pages',
      () async {
        final provider = build();
        final pages = await provider
            .rasterize('/tmp/does-not-matter.pdf', pageIndices: [2, 0])
            .toList();

        expect(pages.map((p) => p.pageIndex).toList(), [2, 0]);
      },
    );

    test(
      'every rasterized page has positive dimensions and non-empty pngBytes',
      () async {
        final provider = build();
        final pages = await provider
            .rasterize('/tmp/does-not-matter.pdf', pageIndices: [0, 1])
            .toList();

        for (final page in pages) {
          expect(page.widthPx, greaterThan(0));
          expect(page.heightPx, greaterThan(0));
          expect(page.pngBytes, isNotEmpty);
        }
      },
    );

    test('info exposes a non-empty provider name', () async {
      final provider = build();
      expect(provider.info.providerName, isNotEmpty);
    });
  });
}

void main() {
  runPdfRasterizerProviderContractTests('fake', FakePdfRasterizerProvider.new);
}
