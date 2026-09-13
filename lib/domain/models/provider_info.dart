/// Stable, provider-agnostic error categories a native or remote provider
/// adapter must normalize its failures into. Vendor-specific codes may only
/// be retained as [ProviderException.diagnosticCode] metadata.
enum ProviderErrorCategory {
  permissionDenied,
  unsupportedDevice,
  modelUnavailable,
  processingFailed,
  cancelled,
  recoverableLowQuality,
  storageUnavailable,
  network,
  unknown,
}

/// Thrown by any provider adapter. Never leaks vendor exception types across
/// the platform boundary into Flutter feature code.
class ProviderException implements Exception {
  const ProviderException(
    this.category,
    this.message, {
    this.diagnosticCode,
    this.providerName,
  });

  final ProviderErrorCategory category;
  final String message;

  /// Vendor-specific code retained only for diagnostics/telemetry.
  final String? diagnosticCode;
  final String? providerName;

  @override
  String toString() =>
      'ProviderException($category, $message'
      '${providerName != null ? ", provider: $providerName" : ""}'
      '${diagnosticCode != null ? ", code: $diagnosticCode" : ""})';
}

/// Identity of a concrete provider implementation, persisted alongside every
/// derived artifact (processed page, OCR block, export) so results can be
/// reproduced, invalidated, or regenerated after a provider change.
class ProviderInfo {
  const ProviderInfo({
    required this.providerName,
    required this.adapterVersion,
    this.modelVersion,
    this.processingOptions = const {},
  });

  final String providerName;
  final String adapterVersion;
  final String? modelVersion;
  final Map<String, String> processingOptions;

  Map<String, Object?> toJson() => {
    'providerName': providerName,
    'adapterVersion': adapterVersion,
    'modelVersion': modelVersion,
    'processingOptions': processingOptions,
  };

  factory ProviderInfo.fromJson(Map<String, Object?> json) => ProviderInfo(
    providerName: json['providerName'] as String,
    adapterVersion: json['adapterVersion'] as String,
    modelVersion: json['modelVersion'] as String?,
    processingOptions:
        (json['processingOptions'] as Map?)?.cast<String, String>() ?? const {},
  );

  @override
  bool operator ==(Object other) =>
      other is ProviderInfo &&
      other.providerName == providerName &&
      other.adapterVersion == adapterVersion &&
      other.modelVersion == modelVersion;

  @override
  int get hashCode => Object.hash(providerName, adapterVersion, modelVersion);

  @override
  String toString() =>
      '$providerName@$adapterVersion'
      '${modelVersion != null ? " (model $modelVersion)" : ""}';
}

/// Capabilities a concrete provider composition can offer on the current
/// device. The Flutter UI must query this rather than assume a capability
/// exists, per SPEC 9.7 capability discovery requirement.
class ScannerCapabilities {
  const ScannerCapabilities({
    required this.liveEdgeDetection,
    required this.offlineOcr,
    required this.handwritingOcr,
    required this.bookDewarping,
    required this.fingerRemoval,
    required this.supportedOcrLanguages,
    required this.torch,
    required this.opticalZoom,
  });

  final bool liveEdgeDetection;
  final bool offlineOcr;
  final bool handwritingOcr;
  final bool bookDewarping;
  final bool fingerRemoval;
  final Set<String> supportedOcrLanguages;
  final bool torch;
  final bool opticalZoom;

  static const ScannerCapabilities none = ScannerCapabilities(
    liveEdgeDetection: false,
    offlineOcr: false,
    handwritingOcr: false,
    bookDewarping: false,
    fingerRemoval: false,
    supportedOcrLanguages: {},
    torch: false,
    opticalZoom: false,
  );
}
