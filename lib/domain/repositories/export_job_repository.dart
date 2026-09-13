import '../models/export_job.dart';

abstract interface class ExportJobRepository {
  Stream<ExportJob?> watchJob(String jobId);

  Stream<List<ExportJob>> watchJobsForProject(String projectId);

  Future<ExportJob> createJob(ExportJob job);

  Future<void> updateJob(ExportJob job);

  Future<void> cancelJob(String jobId);
}
