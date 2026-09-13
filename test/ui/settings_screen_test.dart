import 'package:bookscanner/domain/repositories/settings_repository.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/settings/view_models/settings_view_model.dart';
import 'package:bookscanner/ui/features/settings/views/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// `SettingsViewModel` talks to the real `local_auth` plugin, which has no
// platform implementation registered under `flutter_test` and throws
// `MissingPluginException` for every call. That's caught as an `Exception`
// inside `SettingsViewModel.initialize`/`_authenticate` and treated as
// "biometrics unavailable", which is exactly the real-world fallback for a
// device without biometrics/PIN configured -- so no fake is needed for it,
// and it also means the app-lock switch is expected to render disabled here.

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings = const AppSettings();
  final updateCalls = <AppSettings>[];

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    updateCalls.add(settings);
  }

  @override
  Stream<AppSettings> watchSettings() => Stream.value(_settings);
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  late _FakeSettingsRepository settingsRepository;

  setUp(() {
    settingsRepository = _FakeSettingsRepository();
  });

  SettingsViewModel buildViewModel() =>
      SettingsViewModel(settingsRepository: settingsRepository);

  testWidgets('renders all settings rows with defaults and disabled app lock', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(_wrap(SettingsScreen(viewModel: viewModel)));
    await tester.pump();

    expect(find.byKey(const ValueKey('settingsAppLockSwitch')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settingsStripLocationSwitch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settingsModelTrainingSwitch')),
      findsOneWidget,
    );
    expect(
      find.text('Not enabled — all processing stays on this device'),
      findsOneWidget,
    );

    // No platform biometrics/PIN in the test environment, so app lock must
    // render disabled rather than silently accepting a toggle it can't back.
    final appLockSwitch = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settingsAppLockSwitch')),
    );
    expect(appLockSwitch.onChanged, isNull);
    expect(
      find.text('Biometrics/PIN not available on this device'),
      findsOneWidget,
    );
  });

  testWidgets('toggling strip-location switch persists the change', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(_wrap(SettingsScreen(viewModel: viewModel)));
    await tester.pump();

    expect(viewModel.settings.stripLocationMetadata, isTrue);

    await tester.tap(find.byKey(const ValueKey('settingsStripLocationSwitch')));
    await tester.pump();

    expect(viewModel.settings.stripLocationMetadata, isFalse);
    expect(settingsRepository.updateCalls, hasLength(1));
    expect(
      settingsRepository.updateCalls.single.stripLocationMetadata,
      isFalse,
    );

    final toggledSwitch = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('settingsStripLocationSwitch')),
    );
    expect(toggledSwitch.value, isFalse);
  });

  testWidgets('toggling model-training switch persists the change', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await tester.pumpWidget(_wrap(SettingsScreen(viewModel: viewModel)));
    await tester.pump();

    expect(viewModel.settings.modelTrainingOptIn, isFalse);

    await tester.tap(find.byKey(const ValueKey('settingsModelTrainingSwitch')));
    await tester.pump();

    expect(viewModel.settings.modelTrainingOptIn, isTrue);
    expect(settingsRepository.updateCalls, hasLength(1));
    expect(settingsRepository.updateCalls.single.modelTrainingOptIn, isTrue);
  });
}
