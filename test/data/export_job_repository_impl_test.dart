import 'package:bookscanner/data/repositories/export_job_repository_impl.dart';
import 'package:bookscanner/data/repositories/project_repository_impl.dart';
import 'package:bookscanner/domain/models/export_job.dart';
import 'package:bookscanner/domain/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  late ExportJobRepositoryImpl exportJobRepository;
  late String projectId;

  setUp(() async {
    final db = await openTestDatabase();
    exportJobRepository = ExportJobRepositoryImpl(db);
    final projectRepository = ProjectRepositoryImpl(db);
    final project = await projectRepository.createProject(
      type: ProjectType.document,
      title: 'Doc',
    );
    projectId = project.id;
  });

  test('createJob then watchJob reflects progress updates', () async {
    final job = ExportJob(
      id: 'job1',
      projectId: projectId,
      format: ExportFormat.imagePdf,
      status: ExportJobStatus.running,
      createdAt: DateTime.now(),
      pdfOptions: const PdfExportOptions(searchable: false),
    );
    await exportJobRepository.createJob(job);

    await exportJobRepository.updateJob(job.copyWith(progress: 0.5));
    final midway = await exportJobRepository.watchJob('job1').first;
    expect(midway!.progress, 0.5);

    await exportJobRepository.updateJob(
      job.copyWith(
        status: ExportJobStatus.completed,
        progress: 1,
        outputPath: '/tmp/out.pdf',
      ),
    );
    final completed = await exportJobRepository.watchJob('job1').first;
    expect(completed!.status, ExportJobStatus.completed);
    expect(completed.outputPath, '/tmp/out.pdf');
  });

  test('cancelJob sets status to cancelled', () async {
    final job = ExportJob(
      id: 'job2',
      projectId: projectId,
      format: ExportFormat.markdown,
      status: ExportJobStatus.running,
      createdAt: DateTime.now(),
    );
    await exportJobRepository.createJob(job);
    await exportJobRepository.cancelJob('job2');
    final fetched = await exportJobRepository.watchJob('job2').first;
    expect(fetched!.status, ExportJobStatus.cancelled);
  });
}
