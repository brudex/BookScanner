import 'package:flutter/foundation.dart' show compute;

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/page_detection_provider.dart';
import '../page_detection.dart';

/// Cross-platform classical document detector matching SPEC 9.3.
///
/// Pixel work lives in [page_detection.dart] so the enhancement isolate
/// can run the same finder after a single decode rather than a second
/// full-resolution JPEG load.
class DartPageDetectionProvider implements PageDetectionProvider {
  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'dart-edge-baseline',
    adapterVersion: '2.3.0',
  );

  @override
  Future<Quad?> detectQuad(String imagePath) =>
      compute(detectDocumentQuadFromPath, imagePath);
}
