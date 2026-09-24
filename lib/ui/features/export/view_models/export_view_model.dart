import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/export_job_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/repositories/settings_repository.dart';
import '../../../../domain/use_cases/export_images_use_case.dart';
import '../../../../domain/use_cases/export_project_use_case.dart';

class ExportViewModel extends ChangeNotifier {
  ExportViewModel({
    required this.projectId,
    required ProjectRepository projectRepository,
    required ExportJobRepository exportJobRepository,
    required ExportProjectUseCase exportProjectUseCase,
    required SettingsRepository settingsRepository,
    required ExportImagesUseCase exportImagesUseCase,
  }) : _projectRepository = projectRepository,
       _exportJobRepository = exportJobRepository,
       _exportProjectUseCase = exportProjectUseCase,
       _settingsRepository = settingsRepository,
       _exportImagesUseCase = exportImagesUseCase;

  final String projectId;
  final ProjectRepository _projectRepository;
  final ExportJobRepository _exportJobRepository;
  final ExportProjectUseCase _exportProjectUseCase;
  final SettingsRepository _settingsRepository;
  final ExportImagesUseCase _exportImagesUseCase;

  PdfExportOptions _pdfOptions = const PdfExportOptions();
  PdfExportOptions get pdfOptions => _pdfOptions;

  void setPdfOptions(PdfExportOptions value) {
    _pdfOptions = value;
    notifyListeners();
  }

  Future<int> estimatePdfSizeBytes() => _exportProjectUseCase
      .estimatePdfSizeBytes(projectId: projectId, options: _pdfOptions);

  /// Estimates size under [_pdfOptions] with just [imageQuality] swapped for
  /// [quality] -- used by the compress dialog's live preview while the user
  /// is still dragging the slider, before they've applied the change.
  Future<int> estimatePdfSizeBytesFor(double quality) =>
      _exportProjectUseCase.estimatePdfSizeBytes(
        projectId: projectId,
        options: PdfExportOptions(
          pageSize: _pdfOptions.pageSize,
          orientation: _pdfOptions.orientation,
          marginPoints: _pdfOptions.marginPoints,
          imageQuality: quality,
          maxDimensionPx: _pdfOptions.maxDimensionPx,
          searchable: _pdfOptions.searchable,
          watermarkText: _pdfOptions.watermarkText,
          password: _pdfOptions.password,
          ownerPassword: _pdfOptions.ownerPassword,
        ),
      );

  bool _exportingImages = false;
  bool get exportingImages => _exportingImages;

  String? _imagesOutputPath;
  String? get imagesOutputPath => _imagesOutputPath;

  Future<void> exportImages(ImageExportOptions options) async {
    _exportingImages = true;
    _error = null;
    notifyListeners();
    try {
      final output = await _exportImagesUseCase(
        projectId: projectId,
        title: _project?.title ?? 'Untitled',
        options: options,
      );
      _imagesOutputPath = output.outputPath;
    } on Exception catch (e) {
      _error = e;
    } finally {
      _exportingImages = false;
      notifyListeners();
    }
  }

  Project? _project;
  Project? get project => _project;

  ExportJob? _job;
  ExportJob? get job => _job;
  StreamSubscription<ExportJob?>? _jobSubscription;

  Object? _error;
  Object? get error => _error;

  Future<void> initialize() async {
    _project = await _projectRepository.getProject(projectId);
    notifyListeners();
  }

  /// SPEC 6.10: "Provide a configurable acknowledgement before very large
  /// book exports." Checked by the screen before calling [startExport].
  Future<bool> needsLargeExportAcknowledgement() async {
    final pageCount = _project?.pageOrder.length ?? 0;
    final settings = await _settingsRepository.getSettings();
    return pageCount > settings.largeExportAcknowledgedPageThreshold;
  }

  int get pageCount => _project?.pageOrder.length ?? 0;

  Future<void> startExport(ExportFormat format) async {
    _error = null;
    notifyListeners();
    try {
      final job = await _exportProjectUseCase.export(
        projectId: projectId,
        title: _project?.title ?? 'Untitled',
        format: format,
        author: _project?.metadata.author,
        language: _project?.metadata.language ?? 'en',
        isbn: _project?.metadata.isbn,
        pdfOptions: _pdfOptions,
        markdownOptions: const MarkdownExportOptions(),
        docxOptions: const DocxExportOptions(),
      );
      _job = job;
      _jobSubscription?.cancel();
      _jobSubscription = _exportJobRepository.watchJob(job.id).listen((j) {
        _job = j;
        notifyListeners();
      });
    } on Exception catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    super.dispose();
  }
}
