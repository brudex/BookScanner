import '../models/geometry.dart';
import '../models/provider_info.dart';

/// Detects a document quadrilateral in an already-captured or imported still
/// image (as opposed to [CaptureProvider]'s live-frame analysis). Used for
/// gallery imports and manual re-detection after a crop reset.
abstract interface class PageDetectionProvider {
  ProviderInfo get info;

  /// Returns null if no confident quad could be found; callers fall back to
  /// [Quad.fullFrame] and manual four-corner correction.
  Future<Quad?> detectQuad(String imagePath);
}
