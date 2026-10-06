import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../../routing/app_router.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../../domain/repositories/settings_repository.dart';
import '../view_models/onboarding_view_model.dart';

/// Dark text on the green button (about 14:1; white on green was ~1.3:1).
const _onAccent = Color(0xFF04140C);

/// Body text: brighter than [AppTheme.homeMuted] so it reads on the backdrop.
const _bodyText = Color(0xFFA9C4B5);

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
        picture: _PhotoPicture(
          image: 'assets/onboarding/scan.jpg',
          label: l10n.onboardingScanChip,
        ),
        icon: LucideIcons.scan,
        title: l10n.onboardingScanTitle,
        body: l10n.onboardingScanBody,
      ),
      _OnboardingSlideData(
        picture: _PhotoPicture(
          image: 'assets/onboarding/book.jpg',
          label: l10n.onboardingBookChip,
        ),
        icon: LucideIcons.bookOpen,
        title: l10n.onboardingBookTitle,
        body: l10n.onboardingBookBody,
      ),
      _OnboardingSlideData(
        picture: const _ExportIllustration(),
        icon: LucideIcons.share,
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
        child: Stack(
          children: [
            const Positioned.fill(child: AppBackdrop()),
            Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Opacity(
                          opacity: isLast ? 0 : 1,
                          child: TextButton(
                            key: const ValueKey('onboardingSkip'),
                            onPressed: isLast ? null : _finish,
                            child: Text(
                              l10n.onboardingSkip,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 16,
                                color: AppTheme.homeText,
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
                        itemBuilder: (context, index) => _OnboardingSlide(
                          data: slides[index],
                          index: index,
                          count: slides.length,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: _PrimaryButton(
                        label: isLast
                            ? l10n.onboardingGetStarted
                            : l10n.onboardingContinue,
                        onPressed: _finishing ? null : _next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(29),
        boxShadow: const [
          BoxShadow(
            color: Color(0x593DFF8A),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: FilledButton(
          key: const ValueKey('onboardingContinueButton'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: _onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(29),
            ),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _onAccent,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(LucideIcons.arrowRight, size: 20, color: _onAccent),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.picture,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Widget picture;
  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.data,
    required this.index,
    required this.count,
  });

  final _OnboardingSlideData data;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: data.picture,
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  bottom: -28,
                  child: _IconBadge(icon: data.icon),
                ),
              ],
            ),
          ),
        ),
        // Dots sit between the picture and the title, clear of the text.
        Padding(
          padding: const EdgeInsets.only(top: 44),
          child: _PageDots(index: index, count: count),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: Column(
            children: [
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.homeText,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 16,
                  color: _bodyText,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? AppTheme.accent : const Color(0x38FFFFFF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppTheme.accent,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.homeBackground, width: 4),
        boxShadow: const [BoxShadow(color: Color(0xAA3DFF8A), blurRadius: 22)],
      ),
      child: Icon(icon, size: 26, color: _onAccent),
    );
  }
}

/// A small dark pill with a glowing dot, laid over a picture.
class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xEB0B1C15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x593DFF8A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0xE63DFF8A), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.homeText,
            ),
          ),
        ],
      ),
    );
  }
}

/// A photo filling the card, with soft fades so the chip and badge read.
class _PhotoPicture extends StatelessWidget {
  const _PhotoPicture({required this.image, required this.label});

  final String image;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(image, fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x5904140C),
                Color(0x0004140C),
                Color(0x0004140C),
                Color(0x8C04140C),
              ],
              stops: [0, 0.22, 0.65, 1],
            ),
          ),
        ),
        Positioned(
          top: 18,
          left: 0,
          right: 0,
          child: Center(child: _Chip(label: label)),
        ),
      ],
    );
  }
}

/// Third slide: one page fanning out to the export formats, with a search
/// hit on the page. Drawn in code so it stays sharp and matches the theme.
class _ExportIllustration extends StatelessWidget {
  const _ExportIllustration();

  // Composition size; it is scaled to fit whatever card size the phone gives.
  static const _w = 363.0;
  static const _h = 440.0;
  static const _cx = _w / 2;
  static const _cy = 214.0;
  static const _spread = 124.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = [
      (
        'PDF',
        l10n.onboardingFormatSearchable,
        const Color(0xFFFF6B5E),
        const Offset(-_spread, -_spread),
      ),
      (
        'DOCX',
        l10n.onboardingFormatWord,
        const Color(0xFF5B9BFF),
        const Offset(_spread, -_spread),
      ),
      (
        'EPUB',
        l10n.onboardingFormatEbook,
        const Color(0xFFB98BFF),
        const Offset(-_spread, _spread),
      ),
      (
        'MD',
        l10n.onboardingFormatMarkdown,
        AppTheme.accent,
        const Offset(_spread, _spread),
      ),
    ];
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xFF1F5C3E),
                  Color(0xFF123826),
                  Color(0xFF0B2318),
                ],
              ),
            ),
          ),
          const CustomPaint(painter: _DotGridPainter()),
          Center(
            child: FittedBox(
              child: SizedBox(
                width: _w,
                height: _h,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ExportPagePainter(
                          center: const Offset(_cx, _cy),
                          targets: [for (final t in tiles) t.$4],
                        ),
                      ),
                    ),
                    for (final (name, caption, color, offset) in tiles)
                      Positioned(
                        left: _cx + offset.dx - 44,
                        top: _cy + offset.dy - 38,
                        child: _FormatTile(
                          name: name,
                          caption: caption,
                          color: color,
                        ),
                      ),
                    Positioned(
                      left: _cx - 72,
                      top: _cy + 92,
                      width: 144,
                      child: _SearchPill(text: l10n.onboardingSearchSample),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.name,
    required this.caption,
    required this.color,
  });

  final String name;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFF0E2219),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(22, 27),
            painter: _FileGlyphPainter(color),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.homeText,
              height: 1.1,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: _bodyText,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1C15),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x993DFF8A), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.homeText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0FFFFFFF);
    for (var x = 14.0; x < size.width; x += 22) {
      for (var y = 14.0; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
    // Soft light behind the composition.
    final center = Offset(size.width / 2, size.height * 0.47);
    canvas.drawCircle(
      center,
      size.shortestSide * 0.65,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppTheme.accent.withValues(alpha: 0.16),
                AppTheme.accent.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.shortestSide * 0.65),
            ),
    );
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}

/// The source page, plus dashed lines from it to each format tile.
class _ExportPagePainter extends CustomPainter {
  _ExportPagePainter({required this.center, required this.targets});

  final Offset center;
  final List<Offset> targets;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.45)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final t in targets) {
      final length = t.distance;
      final step = t / length;
      for (var d = 0.0; d < length; d += 9) {
        canvas.drawLine(
          center + step * d,
          center + step * (d + 4).clamp(0, length),
          dash,
        );
      }
    }

    final page = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 124, height: 168),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      page.shift(const Offset(0, 12)),
      Paint()
        ..color = const Color(0x73000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawRRect(page, Paint()..color = const Color(0xFFF4FBF7));

    final left = page.left + 15;
    final width = page.width - 30;
    final ink = Paint()
      ..color = const Color(0xFF9DB8A9)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(left, page.top + 19),
      Offset(page.left + page.width * 0.62, page.top + 19),
      Paint()
        ..color = const Color(0xFF1D3A2C)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    const lengths = [0.92, 0.86, 0.95, 0.7, 0.9, 0.82, 0.94, 0.6, 0.88, 0.9];
    var y = page.top + 37;
    for (var i = 0; y < page.bottom - 15; i++, y += 12) {
      final end = left + width * lengths[i % lengths.length];
      if (i == 4) {
        // The search hit.
        canvas.drawRRect(
          RRect.fromLTRBR(
            left - 3,
            y - 5,
            left + (end - left) * 0.55 + 3,
            y + 5,
            const Radius.circular(3),
          ),
          Paint()..color = AppTheme.accent.withValues(alpha: 0.55),
        );
      }
      canvas.drawLine(Offset(left, y), Offset(end, y), ink);
    }
  }

  @override
  bool shouldRepaint(covariant _ExportPagePainter oldDelegate) => false;
}

class _FileGlyphPainter extends CustomPainter {
  const _FileGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const fold = 7.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FileGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
