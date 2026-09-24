import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../domain/models/capture_models.dart';
import '../../../../domain/repositories/settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required SettingsRepository settingsRepository,
    LocalAuthentication? localAuth,
  }) : _settingsRepository = settingsRepository,
       _localAuth = localAuth ?? LocalAuthentication();

  final SettingsRepository _settingsRepository;
  final LocalAuthentication _localAuth;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  bool _biometricsAvailable = false;
  bool get biometricsAvailable => _biometricsAvailable;

  Future<void> initialize() async {
    _settings = await _settingsRepository.getSettings();
    try {
      _biometricsAvailable =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } on Exception {
      _biometricsAvailable = false;
    }
    notifyListeners();
  }

  Future<void> setAppLockEnabled(bool value) async {
    if (value) {
      final authenticated = await _authenticate();
      if (!authenticated) return;
    }
    _settings = _settings.copyWith(appLockEnabled: value);
    await _settingsRepository.updateSettings(_settings);
    notifyListeners();
  }

  Future<bool> _authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirm to enable app lock',
      );
    } on Exception {
      return false;
    }
  }

  Future<void> setStripLocationMetadata(bool value) async {
    _settings = _settings.copyWith(stripLocationMetadata: value);
    await _settingsRepository.updateSettings(_settings);
    notifyListeners();
  }

  Future<void> setModelTrainingOptIn(bool value) async {
    _settings = _settings.copyWith(modelTrainingOptIn: value);
    await _settingsRepository.updateSettings(_settings);
    notifyListeners();
  }

  Future<void> _updateCaptureSettings(CaptureSettings value) async {
    _settings = _settings.copyWith(captureSettings: value);
    await _settingsRepository.updateSettings(_settings);
    notifyListeners();
  }

  Future<void> setCountdownSeconds(int value) =>
      _updateCaptureSettings(
        _settings.captureSettings.copyWith(countdownSeconds: value),
      );

  Future<void> setContinuousCapture(bool value) => _updateCaptureSettings(
    _settings.captureSettings.copyWith(continuousCapture: value),
  );

  Future<void> setHapticConfirmation(bool value) => _updateCaptureSettings(
    _settings.captureSettings.copyWith(hapticConfirmation: value),
  );

  Future<void> setAudioConfirmation(bool value) => _updateCaptureSettings(
    _settings.captureSettings.copyWith(audioConfirmation: value),
  );

  /// SPEC 6.4: user-selectable OCR language set (at least English for MVP).
  Future<void> setOcrLanguages(List<String> languages) async {
    final cleaned = languages
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (cleaned.isEmpty) cleaned.add('en');
    _settings = _settings.copyWith(ocrLanguages: cleaned);
    await _settingsRepository.updateSettings(_settings);
    notifyListeners();
  }

  Future<void> toggleOcrLanguage(String languageCode) async {
    final code = languageCode.trim().toLowerCase();
    if (code.isEmpty) return;
    final current = List<String>.from(_settings.ocrLanguages);
    if (current.contains(code)) {
      if (current.length == 1) return; // always keep at least one
      current.remove(code);
    } else {
      current.add(code);
    }
    await setOcrLanguages(current);
  }
}
