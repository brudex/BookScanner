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

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        SettingsViewModel(settingsRepository: locator<SettingsRepository>());
    _viewModel.initialize();
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
          ],
        ),
      ),
    );
  }
}
