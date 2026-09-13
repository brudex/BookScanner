import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../domain/models/export_job.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/repositories/export_job_repository.dart';
import '../../../../domain/repositories/project_repository.dart';
import '../../../../domain/use_cases/export_project_use_case.dart';

class ExportViewModel extends ChangeNotifier {
  ExportViewModel({
    required this.projectId,
    required ProjectRepository projectRepository,
    required ExportJobRepository exportJobRepository,
    required ExportProjectUseCase exportProjectUseCase,
  }) : _projectRepository = projectRepository,
       _exportJobRepository = exportJobRepository,
       _exportProjectUseCase = exportProjectUseCase;

  final String projectId;
  final ProjectRepository _projectRepository;
  final ExportJobRepository _exportJobRepository;
  final ExportProjectUseCase _exportProjectUseCase;

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
        pdfOptions: const PdfExportOptions(),
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
