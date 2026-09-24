import 'package:go_router/go_router.dart';

import '../domain/models/capture_models.dart';
import '../domain/repositories/settings_repository.dart';
import '../ui/core/app_lock_controller.dart';
import '../ui/core/di/service_locator.dart';
import '../ui/core/widgets/not_found_screen.dart';
import '../ui/features/capture/views/capture_screen.dart';
import '../ui/features/export/views/export_screen.dart';
import '../ui/features/library/views/book_setup_screen.dart';
import '../ui/features/library/views/favorites_screen.dart';
import '../ui/features/library/views/folder_contents_screen.dart';
import '../ui/features/library/views/folders_screen.dart';
import '../ui/features/library/views/library_screen.dart';
import '../ui/features/library/views/new_scan_sheet_route.dart';
import '../ui/features/library/views/scans_search_screen.dart';
import '../ui/features/library/views/trash_screen.dart';
import '../ui/features/ocr_review/views/ocr_review_screen.dart';
import '../ui/features/onboarding/views/onboarding_screen.dart';
import '../ui/features/page_operations/views/page_operations_screen.dart';
import '../ui/features/page_review/views/crop_correction_screen.dart';
import '../ui/features/page_review/views/filter_adjustment_screen.dart';
import '../ui/features/page_review/views/page_review_screen.dart';
import '../ui/features/page_review/views/post_capture_edit_screen.dart';
import '../ui/features/page_review/views/spread_split_screen.dart';
import '../ui/features/settings/views/settings_screen.dart';
import '../ui/features/settings/views/unlock_screen.dart';

/// Route paths. Kept as constants (not scattered string literals) so screens
/// and tests reference the same source of truth (SPEC 18.1).
class AppRoutes {
  AppRoutes._();

  static const library = '/';
  static const onboarding = '/onboarding';
  static const unlock = '/unlock';
  static const favorites = '/favorites';
  static const trash = '/trash';
  static const folders = '/folders';
  static const scansSearch = '/scans';
  static const folderContents = '/folders/:folderId';
  static const newScan = '/new-scan';
  static const capture = '/projects/:projectId/capture';
  static const bookSetup = '/projects/:projectId/book-setup';
  static const pageReview = '/projects/:projectId/review';
  static const ocrReview = '/projects/:projectId/pages/:pageId/ocr';
  static const cropCorrection = '/projects/:projectId/pages/:pageId/crop';
  static const filterAdjustment = '/projects/:projectId/pages/:pageId/adjust';
  static const postCaptureEdit = '/projects/:projectId/post-capture-edit';
  static const spreadSplit = '/projects/:projectId/pages/:pageId/spread-split';
  static const export = '/projects/:projectId/export';
  static const pageOperations = '/projects/:projectId/compose';
  static const settings = '/settings';

  static String captureFor(String projectId) => '/projects/$projectId/capture';
  static String bookSetupFor(String projectId) =>
      '/projects/$projectId/book-setup';
  static String pageReviewFor(String projectId) =>
      '/projects/$projectId/review';
  static String ocrReviewFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/ocr';
  static String cropCorrectionFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/crop';
  static String filterAdjustmentFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/adjust';
  static String postCaptureEditFor(String projectId) =>
      '/projects/$projectId/post-capture-edit';
  static String spreadSplitFor(String projectId, String pageId) =>
      '/projects/$projectId/pages/$pageId/spread-split';
  static String folderContentsFor(String folderId) => '/folders/$folderId';
  static String exportFor(String projectId) => '/projects/$projectId/export';
  static String pageOperationsFor(String projectId) =>
      '/projects/$projectId/compose';
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.library,
  errorBuilder: (context, state) => NotFoundScreen(error: state.error),
  redirect: (context, state) async {
    if (state.matchedLocation != AppRoutes.library) return null;
    final settings = await locator<SettingsRepository>().getSettings();
    if (!settings.hasCompletedOnboarding) return AppRoutes.onboarding;
    if (settings.appLockEnabled &&
        !locator<AppLockController>().unlockedThisSession) {
      return AppRoutes.unlock;
    }
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.library,
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.unlock,
      builder: (context, state) => const UnlockScreen(),
    ),
    GoRoute(
      path: AppRoutes.favorites,
      builder: (context, state) => const FavoritesScreen(),
    ),
    GoRoute(
      path: AppRoutes.trash,
      builder: (context, state) => const TrashScreen(),
    ),
    GoRoute(
      path: AppRoutes.folders,
      builder: (context, state) => const FoldersScreen(),
    ),
    GoRoute(
      path: AppRoutes.scansSearch,
      builder: (context, state) => const ScansSearchScreen(),
    ),
    GoRoute(
      path: AppRoutes.folderContents,
      builder: (context, state) => FolderContentsScreen(
        folderId: state.pathParameters['folderId']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.newScan,
      builder: (context, state) => const NewScanSheetRoute(),
    ),
    GoRoute(
      path: AppRoutes.bookSetup,
      builder: (context, state) =>
          BookSetupScreen(projectId: state.pathParameters['projectId']!),
    ),
    GoRoute(
      path: AppRoutes.capture,
      // `extra` is either a pageId String (Rescan) or a [CaptureMode]
      // (Home quick action such as Scan ID).
      builder: (context, state) {
        final extra = state.extra;
        return CaptureScreen(
          projectId: state.pathParameters['projectId']!,
          replacePageId: extra is String ? extra : null,
          captureMode: extra is CaptureMode ? extra : null,
        );
      },
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
      builder: (context, state) {
        final extra = state.extra;
        final flowMode = extra == CropFlowMode.postCapture
            ? CropFlowMode.postCapture
            : CropFlowMode.review;
        return CropCorrectionScreen(
          projectId: state.pathParameters['projectId']!,
          pageId: state.pathParameters['pageId']!,
          flowMode: flowMode,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.filterAdjustment,
      builder: (context, state) => FilterAdjustmentScreen(
        projectId: state.pathParameters['projectId']!,
        pageId: state.pathParameters['pageId']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.postCaptureEdit,
      builder: (context, state) => PostCaptureEditScreen(
        projectId: state.pathParameters['projectId']!,
        initialPageId: state.extra as String?,
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
