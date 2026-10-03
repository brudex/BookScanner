import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../data/repositories/export_job_repository_impl.dart';
import '../../../data/repositories/folder_repository_impl.dart';
import '../../../data/repositories/ocr_repository_impl.dart';
import '../../../data/repositories/page_repository_impl.dart';
import '../../../data/repositories/project_repository_impl.dart';
import '../../../data/repositories/settings_repository_impl.dart';
import '../../../data/services/export/adapters/printing_pdf_rasterizer_provider.dart';
import '../../../data/services/export/dart_document_export_provider.dart';
import '../../../data/services/local/app_paths.dart';
import '../../../data/services/local/app_working_session_paths.dart';
import '../../../data/services/local/database_service.dart';
import '../../../data/services/local/file_storage_service.dart';
import '../../../data/services/ocr/adapters/native_ocr_provider.dart';
import '../../../data/services/ocr/ocr_platform_channel.dart';
import '../../../data/services/remote/bookscanner_api_client.dart';
import '../../../data/services/scanner/adapters/cunning_document_scanner_capture_provider.dart';
import '../../../data/services/scanner/adapters/dart_book_dewarp_provider.dart';
import '../../../data/services/scanner/adapters/native_opencv_image_enhancement_provider.dart';
import '../../../data/services/scanner/adapters/native_opencv_page_detection_provider.dart';
import '../../../data/services/scanner/vision_platform_channel.dart';
import '../../../domain/models/capture_models.dart';
import '../../../domain/providers/book_dewarp_provider.dart';
import '../../../domain/providers/capture_provider.dart';
import '../../../domain/providers/conversion_api.dart';
import '../../../domain/providers/document_export_provider.dart';
import '../../../domain/providers/image_enhancement_provider.dart';
import '../../../domain/providers/ocr_provider.dart';
import '../../../domain/providers/page_detection_provider.dart';
import '../../../domain/providers/pdf_rasterizer_provider.dart';
import '../../../domain/repositories/export_job_repository.dart';
import '../../../domain/repositories/folder_repository.dart';
import '../../../domain/repositories/ocr_repository.dart';
import '../../../domain/repositories/page_repository.dart';
import '../../../domain/repositories/project_repository.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../domain/repositories/working_session_path_allocator.dart';
import '../../../domain/use_cases/capture_page_use_case.dart';
import '../../../domain/use_cases/clean_scanned_pages_use_case.dart';
import '../../../domain/use_cases/import_pages_use_case.dart';
import '../../../domain/use_cases/detect_page_anomalies_use_case.dart';
import '../../../domain/use_cases/export_images_use_case.dart';
import '../../../domain/use_cases/export_on_server_use_case.dart';
import '../../../domain/use_cases/export_page_inputs_use_case.dart';
import '../../../domain/use_cases/export_project_use_case.dart';
import '../../../domain/use_cases/load_page_source_use_case.dart';
import '../../../domain/use_cases/load_project_page_inputs_use_case.dart';
import '../../../domain/use_cases/process_book_spread_use_case.dart';
import '../../../domain/use_cases/run_ocr_use_case.dart';
import '../app_lock_controller.dart';

final GetIt locator = GetIt.instance;

/// Composition root (SPEC 9.7: "Provider selection belongs in a
/// composition/configuration layer"). This is the only file in the app
/// allowed to choose a concrete provider implementation by platform; every
/// other layer depends only on the abstract domain interfaces registered
/// here.
Future<void> setupServiceLocator() async {
  final paths = await AppPaths.instance();
  locator.registerSingleton<AppPaths>(paths);

  final database = await DatabaseService.open();
  locator.registerSingleton<DatabaseService>(database);

  locator.registerSingleton<FileStorageService>(FileStorageService(paths));

  locator.registerSingleton<ProjectRepository>(ProjectRepositoryImpl(database));
  locator.registerSingleton<PageRepository>(PageRepositoryImpl(database));
  locator.registerSingleton<OcrRepository>(OcrRepositoryImpl(database));
  locator.registerSingleton<ExportJobRepository>(
    ExportJobRepositoryImpl(database),
  );
  locator.registerSingleton<FolderRepository>(FolderRepositoryImpl(database));
  locator.registerSingleton<SettingsRepository>(
    SettingsRepositoryImpl(database),
  );
  locator.registerSingleton<AppLockController>(AppLockController());

  locator.registerFactory<CaptureProvider>(() => _selectCaptureProvider());
  locator.registerSingleton<OcrProvider>(_selectOcrProvider());
  locator.registerSingleton<PageDetectionProvider>(
    NativeOpenCvPageDetectionProvider(VisionPlatformChannel()),
  );
  locator.registerSingleton<ImageEnhancementProvider>(
    NativeOpenCvImageEnhancementProvider(
      VisionPlatformChannel(),
      locator<FileStorageService>(),
    ),
  );
  locator.registerSingleton<DocumentExportProvider>(
    DartDocumentExportProvider(),
  );
  locator.registerSingleton<BookDewarpProvider>(
    DartBookDewarpProvider(locator<FileStorageService>()),
  );
  locator.registerSingleton<PdfRasterizerProvider>(
    PrintingPdfRasterizerProvider(),
  );
  locator.registerSingleton<WorkingSessionPathAllocator>(
    AppWorkingSessionPaths(paths),
  );

  locator.registerFactory<LoadProjectPageInputsUseCase>(
    () => LoadProjectPageInputsUseCase(
      pageRepository: locator<PageRepository>(),
      ocrRepository: locator<OcrRepository>(),
    ),
  );
  locator.registerFactory<CapturePageUseCase>(
    () => CapturePageUseCase(
      pageRepository: locator<PageRepository>(),
      enhancementProvider: locator<ImageEnhancementProvider>(),
      detectionProvider: locator<PageDetectionProvider>(),
      fileStorage: locator<AppPaths>(),
    ),
  );
  // One queue for the app: it keeps cleaning pages after Capture closes.
  locator.registerLazySingleton<CleanScannedPagesUseCase>(
    () => CleanScannedPagesUseCase(
      pageRepository: locator<PageRepository>(),
      capturePageUseCase: locator<CapturePageUseCase>(),
    ),
  );
  locator.registerFactory<ImportPagesUseCase>(
    () => ImportPagesUseCase(
      capturePageUseCase: locator<CapturePageUseCase>(),
      paths: locator<AppPaths>(),
      rasterizer: locator<PdfRasterizerProvider>(),
      storeImage: _storeBoundedImage,
    ),
  );
  locator.registerFactory<ProcessBookSpreadUseCase>(
    () => ProcessBookSpreadUseCase(
      pageRepository: locator<PageRepository>(),
      dewarpProvider: locator<BookDewarpProvider>(),
      detectionProvider: locator<PageDetectionProvider>(),
      enhancementProvider: locator<ImageEnhancementProvider>(),
      fileStorage: locator<AppPaths>(),
    ),
  );
  locator.registerFactory<DetectPageAnomaliesUseCase>(
    () => DetectPageAnomaliesUseCase(
      pageRepository: locator<PageRepository>(),
      ocrRepository: locator<OcrRepository>(),
    ),
  );
  locator.registerFactory<ExportProjectUseCase>(
    () => ExportProjectUseCase(
      pageRepository: locator<PageRepository>(),
      ocrRepository: locator<OcrRepository>(),
      exportJobRepository: locator<ExportJobRepository>(),
      exportProvider: locator<DocumentExportProvider>(),
      paths: locator<AppPaths>(),
      pageInputLoader: locator<LoadProjectPageInputsUseCase>(),
    ),
  );
  locator.registerLazySingleton<ConversionApi>(BookScannerApiClient.new);
  locator.registerFactory<ExportOnServerUseCase>(
    () => ExportOnServerUseCase(
      api: locator<ConversionApi>(),
      pageLoader: locator<LoadProjectPageInputsUseCase>(),
      exportProvider: locator<DocumentExportProvider>(),
      paths: locator<AppPaths>(),
    ),
  );
  locator.registerFactory<ExportImagesUseCase>(
    () => ExportImagesUseCase(
      pageRepository: locator<PageRepository>(),
      ocrRepository: locator<OcrRepository>(),
      exportProvider: locator<DocumentExportProvider>(),
      paths: locator<AppPaths>(),
      pageInputLoader: locator<LoadProjectPageInputsUseCase>(),
    ),
  );
  locator.registerFactory<LoadPageSourceUseCase>(
    () => LoadPageSourceUseCase(
      projectLoader: locator<LoadProjectPageInputsUseCase>(),
      rasterizer: locator<PdfRasterizerProvider>(),
      workingPaths: locator<WorkingSessionPathAllocator>(),
    ),
  );
  locator.registerFactory<ExportPageInputsUseCase>(
    () => ExportPageInputsUseCase(
      exportJobRepository: locator<ExportJobRepository>(),
      exportProvider: locator<DocumentExportProvider>(),
      paths: locator<AppPaths>(),
    ),
  );
  locator.registerFactory<RunOcrUseCase>(
    () => RunOcrUseCase(
      pageRepository: locator<PageRepository>(),
      ocrRepository: locator<OcrRepository>(),
      ocrProvider: locator<OcrProvider>(),
      settingsRepository: locator<SettingsRepository>(),
    ),
  );
}

/// Copies a scanned or imported image into app storage with its long side
/// capped at [StoredPageLimits.maxLongSidePx] (native, low-memory decode).
Future<void> _storeBoundedImage(String source, String dest) async {
  try {
    await VisionPlatformChannel().downscaleStill(
      sourcePath: source,
      outputPath: dest,
      maxLongSide: StoredPageLimits.maxLongSidePx,
    );
  } on PlatformException {
    // Keep the page even if bounding it failed; Review can still show it,
    // just more slowly.
    await File(source).copy(dest);
  }
}

/// Documents, IDs and books all use the system document scanner (ML Kit on
/// Android, VisionKit on iOS): its trained page detector is far more
/// reliable than the in-app OpenCV preview. The in-app CameraX/AVFoundation
/// pipeline (`NativeCaptureProvider` behind `ModeAwareCaptureProvider`) is
/// kept in the repo, unregistered, so books can move back to it later.
CaptureProvider _selectCaptureProvider() {
  if (Platform.isAndroid || Platform.isIOS) {
    return CunningDocumentScannerCaptureProvider(
      paths: locator<AppPaths>(),
      persistStill: _storeBoundedImage,
    );
  }
  throw UnsupportedError(
    'No capture provider is registered for this platform. '
    'BookScanner targets Android and iOS only.',
  );
}

/// Selects the OCR provider by platform, mirroring [_selectCaptureProvider].
OcrProvider _selectOcrProvider() {
  final channel = OcrPlatformChannel();
  if (Platform.isAndroid) {
    return NativeOcrProvider(channel, platformLabel: 'android');
  }
  if (Platform.isIOS) {
    return NativeOcrProvider(channel, platformLabel: 'ios');
  }
  throw UnsupportedError(
    'No OCR provider is registered for this platform. '
    'BookScanner targets Android and iOS only.',
  );
}
