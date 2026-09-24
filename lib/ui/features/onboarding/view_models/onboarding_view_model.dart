import 'package:flutter/foundation.dart';

import '../../../../domain/repositories/settings_repository.dart';

class OnboardingViewModel extends ChangeNotifier {
  OnboardingViewModel({required SettingsRepository settingsRepository})
    : _settingsRepository = settingsRepository;

  final SettingsRepository _settingsRepository;

  Future<void> complete() async {
    final settings = await _settingsRepository.getSettings();
    await _settingsRepository.updateSettings(
      settings.copyWith(hasCompletedOnboarding: true),
    );
  }
}
