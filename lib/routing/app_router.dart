import 'package:go_router/go_router.dart';

import '../ui/core/widgets/not_found_screen.dart';
import '../ui/features/capture/views/capture_screen.dart';
import '../ui/features/export/views/export_screen.dart';
import '../ui/features/library/views/library_screen.dart';
import '../ui/features/library/views/new_scan_sheet_route.dart';
import '../ui/features/ocr_review/views/ocr_review_screen.dart';
import '../ui/features/page_operations/views/page_operations_screen.dart';
import '../ui/features/page_review/views/crop_correction_screen.dart';
import '../ui/features/page_review/views/filter_adjustment_screen.dart';
import '../ui/features/page_review/views/page_review_screen.dart';
import '../ui/features/page_review/views/spread_split_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';

/// Route paths. Kept as constants (not scattered string literals) so screens
/// and tests reference the same source of truth (SPEC 18.1).
class AppRoutes {
  AppRoutes._();

  static const library = '/';
  static const newScan = '/new-scan';
  static const capture = '/projects/:projectId/capture';
  static const pageReview = '/projects/:projectId/review';
  static const ocrReview = '/projects/:projectId/pages/:pageId/ocr';
  static const cropCorrection = '/projects/:projectId/pages/:pageId/crop';
  static const filterAdjustment = '/projects/:projectId/pages/:pageId/adjust';
  static const spreadSplit = '/projects/:projectId/pages/:pageId/spread-split';
  static const export = '/projects/:projectId/export';
  static const pageOperations = '/projects/:projectId/compose';
  static const settings = '/settings';

  static String captureFor(String projectId) => '/projects/$projectId/capture';
  static String pageReviewFor(String projectId) =>
      '/projects/$projectId/review';
  static String ocrReviewFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/ocr';
  static String cropCorrectionFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/crop';
  static String filterAdjustmentFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/adjust';
  static String spreadSplitFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/spread-split';
  static String exportFor(String projectId) => '/projects/$projectId/export';
  static String pageOperationsFor(String projectId) =>
      '/projects/$projectId/compose';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.library,
  errorBuilder: (context, state) => NotFoundScreen(error: state.error),
  routes: [
    GoRoute(
      path: AppRoutes.library,
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: AppRoutes.newScan,
      builder: (context, state) => const NewScanSheetRoute(),
    ),
    GoRoute(
      path: AppRoutes.capture,
      // `extra` optionally carries the pageId to replace in place (the
      // "Rescan" action from Page Review) rather than appending a new page
      // -- not part of the path, since it's a one-off action parameter, not
      // a distinct navigable location.
      builder: (context, state) => CaptureScreen(
        projectId: state.pathParameters['projectId']!,
        replacePageId: state.extra as String?,
      ),
    ),
    GoRoute(
      path: AppRoutes.pageReview,
      builder: (context, state) =>
          PageReviewScreen(projectId: state.pathParameters['projectId']!),
    ),
    GoRoute(
      path: AppRoutes.ocrReview,
      builder: (context, state) => OcrReviewScreen(
        projectId: state.pathParameters['projectId']!,
        pageId: state.pathParameters['pageId']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.cropCorrection,
      builder: (context, state) => CropCorrectionScreen(
        projectId: state.pathParameters['projectId']!,
        pageId: state.pathParameters['pageId']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.filterAdjustment,
      builder: (context, state) => FilterAdjustmentScreen(
        projectId: state.pathParameters['projectId']!,
        pageId: state.pathParameters['pageId']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.spreadSplit,
      builder: (context, state) => SpreadSplitScreen(
        projectId: state.pathParameters['projectId']!,
        pageId: state.pathParameters['pageId']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.export,
      builder: (context, state) =>
          ExportScreen(projectId: state.pathParameters['projectId']!),
    ),
    GoRoute(
      path: AppRoutes.pageOperations,
      builder: (context, state) =>
          PageOperationsScreen(projectId: state.pathParameters['projectId']!),
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
