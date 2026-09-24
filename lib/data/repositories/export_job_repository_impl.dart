import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/export_job.dart';
import '../../domain/repositories/export_job_repository.dart';
import '../services/local/database_service.dart';

class ExportJobRepositoryImpl implements ExportJobRepository {
  ExportJobRepositoryImpl(this._databaseService);

  final DatabaseService _databaseService;
  final _changes = StreamController<String>.broadcast();

  Database get _db => _databaseService.db;

  @override
  Stream<ExportJob?> watchJob(String jobId) async* {
    yield await _get(jobId);
    await for (final changed in _changes.stream) {
      if (changed == jobId) yield await _get(jobId);
    }
  }

  @override
  Stream<List<ExportJob>> watchJobsForProject(String projectId) async* {
    yield await _listForProject(projectId);
    await for (final _ in _changes.stream) {
      yield await _listForProject(projectId);
    }
  }

  Future<ExportJob?> _get(String jobId) async {
    final rows = await _db.query(
      'export_jobs',
      where: 'id = ?',
      whereArgs: [jobId],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<List<ExportJob>> _listForProject(String projectId) async {
    final rows = await _db.query(
      'export_jobs',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<ExportJob> createJob(ExportJob job) async {
    await _db.insert('export_jobs', _toRow(job));
    _changes.add(job.id);
    return job;
  }

  @override
  Future<void> updateJob(ExportJob job) async {
    await _db.update(
      'export_jobs',
      _toRow(job),
      where: 'id = ?',
      whereArgs: [job.id],
    );
    _changes.add(job.id);
  }

  @override
  Future<void> cancelJob(String jobId) async {
    await _db.update(
      'export_jobs',
      {'status': ExportJobStatus.cancelled.name},
      where: 'id = ?',
      whereArgs: [jobId],
    );
    _changes.add(jobId);
  }

  static Map<String, Object?> _toRow(ExportJob job) => {
    'id': job.id,
    'project_id': job.projectId,
    'format': job.format.name,
    'status': job.status.name,
    'progress': job.progress,
    'error': job.error,
    'output_path': job.outputPath,
    'created_at': job.createdAt.millisecondsSinceEpoch,
    'completed_at': job.completedAt?.millisecondsSinceEpoch,
    'pdf_options': job.pdfOptions == null
        ? null
        : jsonEncode({
            'pageSize': job.pdfOptions!.pageSize.name,
            'orientation': job.pdfOptions!.orientation.name,
            'marginPoints': job.pdfOptions!.marginPoints,
            'imageQuality': job.pdfOptions!.imageQuality,
            'maxDimensionPx': job.pdfOptions!.maxDimensionPx,
            'searchable': job.pdfOptions!.searchable,
            'password': job.pdfOptions!.password,
            'ownerPassword': job.pdfOptions!.ownerPassword,
            'watermarkText': job.pdfOptions!.watermarkText,
          }),
    'markdown_options': job.markdownOptions == null
        ? null
        : jsonEncode({
            'includePageBoundaryComments':
                job.markdownOptions!.includePageBoundaryComments,
            'includeFrontMatter': job.markdownOptions!.includeFrontMatter,
            'packageAsZip': job.markdownOptions!.packageAsZip,
          }),
    'docx_options': job.docxOptions == null
        ? null
        : jsonEncode({'pageMode': job.docxOptions!.pageMode.name}),
  };

  static ExportJob _fromRow(Map<String, Object?> row) {
    final pdfJson = row['pdf_options'] as String?;
    final mdJson = row['markdown_options'] as String?;
    final docxJson = row['docx_options'] as String?;
    return ExportJob(
      id: row['id']! as String,
      projectId: row['project_id']! as String,
      format: ExportFormat.values.byName(row['format']! as String),
      status: ExportJobStatus.values.byName(row['status']! as String),
      progress: (row['progress']! as num).toDouble(),
      error: row['error'] as String?,
      outputPath: row['output_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['completed_at']! as int),
      pdfOptions: pdfJson == null
          ? null
          : () {
              final m = jsonDecode(pdfJson) as Map<String, Object?>;
              return PdfExportOptions(
                pageSize: PdfPageSize.values.byName(m['pageSize']! as String),
                orientation: PdfOrientation.values.byName(
                  m['orientation']! as String,
                ),
                marginPoints: (m['marginPoints']! as num).toDouble(),
                imageQuality: (m['imageQuality']! as num).toDouble(),
                maxDimensionPx: (m['maxDimensionPx'] as num?)?.toInt(),
                searchable: m['searchable']! as bool,
                password: m['password'] as String?,
                ownerPassword: m['ownerPassword'] as String?,
                watermarkText: m['watermarkText'] as String?,
              );
            }(),
      markdownOptions: mdJson == null
          ? null
          : () {
              final m = jsonDecode(mdJson) as Map<String, Object?>;
              return MarkdownExportOptions(
                includePageBoundaryComments:
                    m['includePageBoundaryComments']! as bool,
                includeFrontMatter: m['includeFrontMatter']! as bool,
                packageAsZip: m['packageAsZip']! as bool,
              );
            }(),
      docxOptions: docxJson == null
          ? null
          : DocxExportOptions(
              pageMode: DocxPageMode.values.byName(
                (jsonDecode(docxJson) as Map<String, Object?>)['pageMode']!
                    as String,
              ),
            ),
    );
  }
}
