import '../models/capture_models.dart';

class AppSettings {
  const AppSettings({
    this.appLockEnabled = false,
    this.cloudProcessingConsentGiven = false,
    this.cloudProcessingConsentAtMs,
    this.modelTrainingOptIn = false,
    this.stripLocationMetadata = true,
    this.captureSettings = const CaptureSettings(),
    this.ocrLanguages = const ['en'],
    this.hasSeenCopyrightNotice = false,
    this.largeExportAcknowledgedPageThreshold = 300,
    this.hasCompletedOnboarding = false,
  });

  final bool appLockEnabled;
  final bool cloudProcessingConsentGiven;
  final int? cloudProcessingConsentAtMs;
  final bool modelTrainingOptIn;
  final bool stripLocationMetadata;
  final CaptureSettings captureSettings;
  final List<String> ocrLanguages;
  final bool hasSeenCopyrightNotice;
  final int largeExportAcknowledgedPageThreshold;
  final bool hasCompletedOnboarding;

  AppSettings copyWith({
    bool? appLockEnabled,
    bool? cloudProcessingConsentGiven,
    int? cloudProcessingConsentAtMs,
    bool? modelTrainingOptIn,
    bool? stripLocationMetadata,
    CaptureSettings? captureSettings,
    List<String>? ocrLanguages,
    bool? hasSeenCopyrightNotice,
    int? largeExportAcknowledgedPageThreshold,
    bool? hasCompletedOnboarding,
  }) => AppSettings(
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    cloudProcessingConsentGiven:
        cloudProcessingConsentGiven ?? this.cloudProcessingConsentGiven,
    cloudProcessingConsentAtMs:
        cloudProcessingConsentAtMs ?? this.cloudProcessingConsentAtMs,
    modelTrainingOptIn: modelTrainingOptIn ?? this.modelTrainingOptIn,
    stripLocationMetadata: stripLocationMetadata ?? this.stripLocationMetadata,
    captureSettings: captureSettings ?? this.captureSettings,
    ocrLanguages: ocrLanguages ?? this.ocrLanguages,
    hasSeenCopyrightNotice:
        hasSeenCopyrightNotice ?? this.hasSeenCopyrightNotice,
    largeExportAcknowledgedPageThreshold:
        largeExportAcknowledgedPageThreshold ??
        this.largeExportAcknowledgedPageThreshold,
    hasCompletedOnboarding:
        hasCompletedOnboarding ?? this.hasCompletedOnboarding,
  );
}

/// Local-only app settings and consent state (SPEC 6.9, 6.10). No account is
/// required to read or write these.
abstract interface class SettingsRepository {
  Stream<AppSettings> watchSettings();

  Future<AppSettings> getSettings();

  Future<void> updateSettings(AppSettings settings);
}
