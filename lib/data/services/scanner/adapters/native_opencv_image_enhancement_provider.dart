import 'package:path/path.dart' as p;

import '../../../../domain/models/geometry.dart';
import '../../../../domain/models/provider_info.dart';
import '../../../../domain/models/scan_page.dart';
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
    if (request.passthrough) return _fallback.enhance(request);
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
      // Native warp/filter ignores brightness/contrast/sharpness — apply
      // those as a Dart pass on the already-processed page when needed.
      final needsAdjust =
          request.brightness != 0 ||
          request.contrast != 0 ||
          request.sharpness != 0;
      final processedPath = needsAdjust
          ? (await _fallback.enhance(
              EnhancementRequest(
                sourceImagePath: native.processedImagePath,
                outputImagePath: request.outputImagePath,
                cropPoints: Quad.fullFrame,
                rotationDegrees: 0,
                filter: PageFilter.original,
                brightness: request.brightness,
                contrast: request.contrast,
                sharpness: request.sharpness,
                removeShadowsAndStains: false,
                detectCrop: false,
              ),
            )).processedImagePath
          : native.processedImagePath;
      final pageId = p.basenameWithoutExtension(request.outputImagePath);
      final thumbnailPath = await _fileStorage.generateThumbnail(
        processedPath,
        pageId,
      );
      return EnhancementResult(
        processedImagePath: processedPath,
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
