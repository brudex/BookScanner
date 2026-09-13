import 'package:flutter/services.dart';

import '../../../domain/models/geometry.dart';
import '../../../domain/models/provider_info.dart';
import 'vision_channel_contract.dart';

class VisionAvailability {
  const VisionAvailability({
    required this.available,
    required this.opencvVersion,
    required this.algorithmVersion,
  });

  final bool available;
  final String opencvVersion;
  final String algorithmVersion;
}

class VisionDetectResult {
  const VisionDetectResult({
    required this.quad,
    required this.confidence,
    required this.qualityScore,
    required this.providerInfo,
  });

  final Quad? quad;
  final double confidence;
  final double qualityScore;
  final ProviderInfo providerInfo;
}

class VisionEnhanceResult {
  const VisionEnhanceResult({
    required this.processedImagePath,
    required this.crop,
    required this.qualityScore,
    required this.providerInfo,
  });

  final String processedImagePath;
  final Quad crop;
  final double qualityScore;
  final ProviderInfo providerInfo;
}

/// Service wrapper around the path-based vision plugin. No image bytes
/// travel on this channel.
class VisionPlatformChannel {
  VisionPlatformChannel({MethodChannel? methodChannel})
    : _channel =
          methodChannel ??
          const MethodChannel(VisionChannelContract.methodChannelName);

  final MethodChannel _channel;

  Future<VisionAvailability> isAvailable() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        VisionChannelContract.methodIsAvailable,
      );
      if (map == null) {
        return const VisionAvailability(
          available: false,
          opencvVersion: '',
          algorithmVersion: '',
        );
      }
      return VisionAvailability(
        available: map['available'] as bool? ?? false,
        opencvVersion: map['opencvVersion'] as String? ?? '',
        algorithmVersion: map['algorithmVersion'] as String? ?? '',
      );
    } on MissingPluginException {
      return const VisionAvailability(
        available: false,
        opencvVersion: '',
        algorithmVersion: '',
      );
    }
  }

  Future<VisionDetectResult> detectStill(String path) async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>(
      VisionChannelContract.methodDetectStill,
      {'path': path},
    );
    if (map == null) {
      throw const ProviderException(
        ProviderErrorCategory.processingFailed,
        'Null vision detect result',
      );
    }
    final quadMap = map['quad'] as Map<Object?, Object?>?;
    return VisionDetectResult(
      quad: quadMap == null ? null : Quad.fromJson(quadMap),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      qualityScore: (map['qualityScore'] as num?)?.toDouble() ?? 0,
      providerInfo: ProviderInfo(
        providerName: map['providerName'] as String? ?? 'native-opencv',
        adapterVersion: map['adapterVersion'] as String? ?? '1.0.0',
        modelVersion: map['opencvVersion'] as String?,
      ),
    );
  }

  Future<VisionEnhanceResult> enhanceStill({
    required String sourcePath,
    required String outputPath,
    required Quad crop,
    required bool detectCrop,
    required String filter,
    required bool removeShadowsAndStains,
  }) async {
    final map = await _channel.invokeMethod<Map<Object?, Object?>>(
      VisionChannelContract.methodEnhanceStill,
      {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'crop': [
          crop.topLeft.x,
          crop.topLeft.y,
          crop.topRight.x,
          crop.topRight.y,
          crop.bottomRight.x,
          crop.bottomRight.y,
          crop.bottomLeft.x,
          crop.bottomLeft.y,
        ],
        'detectCrop': detectCrop,
        'filter': filter,
        'removeShadowsAndStains': removeShadowsAndStains,
      },
    );
    if (map == null) {
      throw const ProviderException(
        ProviderErrorCategory.processingFailed,
        'Null vision enhance result',
      );
    }
    final cropMap = map['crop'] as Map<Object?, Object?>?;
    return VisionEnhanceResult(
      processedImagePath: map['processedImagePath']! as String,
      crop: cropMap == null ? Quad.fullFrame : Quad.fromJson(cropMap),
      qualityScore: (map['qualityScore'] as num?)?.toDouble() ?? 0,
      providerInfo: ProviderInfo(
        providerName: map['providerName'] as String? ?? 'native-opencv',
        adapterVersion: map['adapterVersion'] as String? ?? '1.0.0',
        modelVersion: map['opencvVersion'] as String?,
      ),
    );
  }

  Future<double> scoreStill(String path) async {
    final score = await _channel.invokeMethod<double>(
      VisionChannelContract.methodScoreStill,
      {'path': path},
    );
    return score ?? 0;
  }
}
