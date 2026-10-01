import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../domain/repositories/settings_repository.dart';
import '../view_models/onboarding_view_model.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.viewModel});

  /// Injectable for widget tests; production code leaves this null and gets
  /// a real instance wired through the composition root.
  final OnboardingViewModel? viewModel;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final OnboardingViewModel _viewModel;
  final _pageController = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _pageCount = 3;

  @override
  void initState() {
    super.initState();
    _viewModel =
        widget.viewModel ??
        OnboardingViewModel(settingsRepository: locator<SettingsRepository>());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _viewModel.complete();
    if (!mounted) return;
    context.go(AppRoutes.library);
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = [
      _OnboardingSlideData(
        image: 'assets/onboarding/scan.jpg',
        icon: LucideIcons.scan,
        title: l10n.onboardingScanTitle,
        body: l10n.onboardingScanBody,
      ),
      _OnboardingSlideData(
        image: 'assets/onboarding/book.jpg',
        icon: LucideIcons.bookOpen,
        title: l10n.onboardingBookTitle,
        body: l10n.onboardingBookBody,
      ),
      _OnboardingSlideData(
        image: 'assets/onboarding/organize.jpg',
        icon: LucideIcons.folderCheck,
        title: l10n.onboardingOrganizeTitle,
        body: l10n.onboardingOrganizeBody,
      ),
    ];
    final isLast = _page == slides.length - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Theme(
        data: AppTheme.homeShell(),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppTheme.homeGradient),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Opacity(
                        opacity: isLast ? 0 : 1,
                        child: TextButton(
                          key: const ValueKey('onboardingSkip'),
                          onPressed: isLast ? null : _finish,
                          child: Text(
                            l10n.onboardingSkip,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: AppTheme.homeMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      key: const ValueKey('onboardingPageView'),
                      controller: _pageController,
                      itemCount: slides.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) =>
                          _OnboardingSlide(data: slides[index]),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? AppTheme.accent
                                : AppTheme.homeHairline,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        key: const ValueKey('onboardingContinueButton'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: _finishing ? null : _next,
                        child: Text(
                          isLast
                              ? l10n.onboardingGetStarted
                              : l10n.onboardingContinue,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.image,
    required this.icon,
    required this.title,
    required this.body,
  });

  final String image;
  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.data});

  final _OnboardingSlideData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.asset(data.image, fit: BoxFit.cover),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: -18,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                      boxShadow: AppTheme.cardShadow,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(data.icon, size: 24, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 0),
          child: Column(
            children: [
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.homeText,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 15,
                  color: AppTheme.homeMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
