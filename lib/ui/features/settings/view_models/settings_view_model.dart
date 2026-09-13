import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

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
}
