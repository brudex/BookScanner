import 'package:bookscanner/domain/repositories/settings_repository.dart';
import 'package:bookscanner/l10n/gen/app_localizations.dart';
import 'package:bookscanner/ui/features/onboarding/view_models/onboarding_view_model.dart';
import 'package:bookscanner/ui/features/onboarding/views/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

  OnboardingViewModel buildViewModel() =>
      OnboardingViewModel(settingsRepository: settingsRepository);

  testWidgets('shows the first slide with Skip visible and Continue label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(OnboardingScreen(viewModel: buildViewModel())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan Documents in Seconds'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboardingSkip')), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
  });

  testWidgets('swiping to the last slide swaps Continue for Get Started', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(OnboardingScreen(viewModel: buildViewModel())),
    );
    await tester.pumpAndSettle();

    final pageView = find.byKey(const ValueKey('onboardingPageView'));
    await tester.fling(pageView, const Offset(-400, 0), 800);
    await tester.pumpAndSettle();
    await tester.fling(pageView, const Offset(-400, 0), 800);
    await tester.pumpAndSettle();

    expect(find.text('Export & Stay Organized'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('completing onboarding marks settings as completed', (
    tester,
  ) async {
    final viewModel = buildViewModel();
    await viewModel.complete();

    expect(settingsRepository.updateCalls, hasLength(1));
    expect(settingsRepository.updateCalls.single.hasCompletedOnboarding, true);
  });
}
