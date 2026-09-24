import 'package:flutter/material.dart';

import '../../../../domain/repositories/settings_repository.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../core/di/service_locator.dart';
import '../view_models/settings_view_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.viewModel});

  final SettingsViewModel? viewModel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsViewModel _viewModel;

  static const _ocrLanguageCodes = [
    'en',
    'es',
    'fr',
    'de',
    'pt',
    'it',
  ];

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        SettingsViewModel(settingsRepository: locator<SettingsRepository>());
    _viewModel.initialize();
  }

  String _ocrLanguageLabel(String code) {
    final l10n = AppLocalizations.of(context);
    return switch (code) {
      'en' => l10n.ocrLanguageEnglish,
      'es' => l10n.ocrLanguageSpanish,
      'fr' => l10n.ocrLanguageFrench,
      'de' => l10n.ocrLanguageGerman,
      'pt' => l10n.ocrLanguagePortuguese,
      'it' => l10n.ocrLanguageItalian,
      _ => code,
    };
  }

  Future<void> _openOcrLanguagesSheet(AppLocalizations l10n) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.settingsOcrLanguages,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final code in _ocrLanguageCodes)
                CheckboxListTile(
                  key: ValueKey('ocrLanguage-$code'),
                  title: Text(_ocrLanguageLabel(code)),
                  value: _viewModel.settings.ocrLanguages.contains(code),
                  onChanged: (_) => _viewModel.toggleOcrLanguage(code),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              key: const ValueKey('settingsAppLockSwitch'),
              title: Text(l10n.settingsAppLock),
              subtitle: _viewModel.biometricsAvailable
                  ? null
                  : const Text('Biometrics/PIN not available on this device'),
              value: _viewModel.settings.appLockEnabled,
              onChanged: _viewModel.biometricsAvailable
                  ? _viewModel.setAppLockEnabled
                  : null,
            ),
            SwitchListTile(
              key: const ValueKey('settingsStripLocationSwitch'),
              title: Text(l10n.settingsStripLocation),
              value: _viewModel.settings.stripLocationMetadata,
              onChanged: _viewModel.setStripLocationMetadata,
            ),
            ListTile(
              key: const ValueKey('settingsOcrLanguagesTile'),
              title: Text(l10n.settingsOcrLanguages),
              subtitle: Text(
                _viewModel.settings.ocrLanguages
                    .map(_ocrLanguageLabel)
                    .join(', '),
              ),
              onTap: () => _openOcrLanguagesSheet(l10n),
            ),
            ListTile(
              title: Text(l10n.settingsCloudProcessing),
              subtitle: Text(
                _viewModel.settings.cloudProcessingConsentGiven
                    ? 'Consent given'
                    : 'Not enabled — all processing stays on this device',
              ),
            ),
            SwitchListTile(
              key: const ValueKey('settingsModelTrainingSwitch'),
              title: const Text('Allow anonymized content for model training'),
              value: _viewModel.settings.modelTrainingOptIn,
              onChanged: _viewModel.setModelTrainingOptIn,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                l10n.settingsCaptureSection,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ListTile(
              key: const ValueKey('settingsCountdownTile'),
              title: Text(l10n.settingsCountdown),
              trailing: DropdownButton<int>(
                key: const ValueKey('settingsCountdownDropdown'),
                value: _viewModel.settings.captureSettings.countdownSeconds,
                items: [0, 3, 5, 10]
                    .map(
                      (seconds) => DropdownMenuItem(
                        value: seconds,
                        child: Text(
                          seconds == 0
                              ? l10n.settingsCountdownOff
                              : '${seconds}s',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) _viewModel.setCountdownSeconds(value);
                },
              ),
            ),
            SwitchListTile(
              key: const ValueKey('settingsContinuousCaptureSwitch'),
              title: Text(l10n.settingsContinuousCapture),
              value: _viewModel.settings.captureSettings.continuousCapture,
              onChanged: _viewModel.setContinuousCapture,
            ),
            SwitchListTile(
              key: const ValueKey('settingsHapticConfirmationSwitch'),
              title: Text(l10n.settingsHapticConfirmation),
              value: _viewModel.settings.captureSettings.hapticConfirmation,
              onChanged: _viewModel.setHapticConfirmation,
            ),
            SwitchListTile(
              key: const ValueKey('settingsAudioConfirmationSwitch'),
              title: Text(l10n.settingsAudioConfirmation),
              value: _viewModel.settings.captureSettings.audioConfirmation,
              onChanged: _viewModel.setAudioConfirmation,
            ),
          ],
        ),
      ),
    );
  }
}
