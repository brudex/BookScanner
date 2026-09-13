import 'package:path/path.dart' as p;

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/providers/image_enhancement_provider.dart';
import '../../local/file_storage_service.dart';
import '../vision_platform_channel.dart';
import 'dart_image_enhancement_provider.dart';

/// Native OpenCV warp/enhance with the Dart baseline as fallback.
class NativeOpenCvImageEnhancementProvider implements ImageEnhancementProvider {
  NativeOpenCvImageEnhancementProvider(
    this._channel,
    this._fileStorage, {
    ImageEnhancementProvider? fallback,
  }) : _fallback = fallback ?? DartImageEnhancementProvider(_fileStorage);

  final VisionPlatformChannel _channel;
  final FileStorageService _fileStorage;
  final ImageEnhancementProvider _fallback;

  @override
  ProviderInfo get info => const ProviderInfo(
    providerName: 'native-opencv-enhance',
    adapterVersion: '1.0.0',
  );

  @override
  Future<double> scoreQuality(String imagePath) async {
    try {
      final availability = await _channel.isAvailable();
      if (!availability.available) return _fallback.scoreQuality(imagePath);
      return _channel.scoreStill(imagePath);
    } on Object {
      return _fallback.scoreQuality(imagePath);
    }
  }

  @override
  Future<EnhancementResult> enhance(EnhancementRequest request) async {
    try {
      final availability = await _channel.isAvailable();
      if (!availability.available) return _fallback.enhance(request);
      final crop = request.cropPoints == Quad.captureGuide
          ? Quad.fullFrame
          : request.cropPoints;
      final native = await _channel.enhanceStill(
        sourcePath: request.sourceImagePath,
        outputPath: request.outputImagePath,
        crop: crop,
        detectCrop: request.detectCrop,
        filter: request.filter.name,
        removeShadowsAndStains: request.removeShadowsAndStains,
      );
      final pageId = p.basenameWithoutExtension(request.outputImagePath);
      final thumbnailPath = await _fileStorage.generateThumbnail(
        native.processedImagePath,
        pageId,
      );
      return EnhancementResult(
        processedImagePath: native.processedImagePath,
        thumbnailPath: thumbnailPath,
        qualityScore: native.qualityScore,
        providerInfo: native.providerInfo,
        cropPoints: native.crop,
      );
    } on Object {
      return _fallback.enhance(request);
    }
  }
}
