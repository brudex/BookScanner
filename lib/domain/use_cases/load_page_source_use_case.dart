import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/page_source.dart';
import '../providers/document_export_provider.dart';
import '../providers/pdf_rasterizer_provider.dart';
import '../repositories/working_session_path_allocator.dart';
import 'load_project_page_inputs_use_case.dart';

/// Turns any [PageSource] into the [ExportPageInput]s a page-composition
/// session can splice into its working list (SPEC 6.5 "editing": merge,
/// insert, replace from another project, an external PDF, or a plain
/// image).
///
/// Picked files (external PDF, image) are always copied into
/// [WorkingSessionPathAllocator] scratch storage rather than referenced at
/// their original path: `file_picker`/`image_picker` paths (in particular
/// iOS security-scoped resources) are not guaranteed to stay readable after
/// the picker UI is dismissed, and every other [ExportPageInput.imagePath]
/// in this app is already an app-owned file, not an external one.
class LoadPageSourceUseCase {
  LoadPageSourceUseCase({
    required LoadProjectPageInputsUseCase projectLoader,
    required PdfRasterizerProvider rasterizer,
    required WorkingSessionPathAllocator workingPaths,
    Uuid? uuid,
  }) : _projectLoader = projectLoader,
       _rasterizer = rasterizer,
       _workingPaths = workingPaths,
       _uuid = uuid ?? const Uuid();

  final LoadProjectPageInputsUseCase _projectLoader;
  final PdfRasterizerProvider _rasterizer;
  final WorkingSessionPathAllocator _workingPaths;
  final Uuid _uuid;

  Future<List<ExportPageInput>> call(
    PageSource source, {
    required String sessionId,
  }) async {
    switch (source) {
      case ProjectPageSource(:final projectId):
        return _projectLoader(projectId);

      case ExternalPdfPageSource(:final pdfPath, :final pageIndices):
        final inputs = <ExportPageInput>[];
        await for (final raster in _rasterizer.rasterize(
          pdfPath,
          pageIndices: pageIndices,
          dpi: 150,
        )) {
          final pageId = _uuid.v4();
          final path = _workingPaths.pagePathFor(sessionId, pageId, ext: 'png');
          await File(path).writeAsBytes(raster.pngBytes);
          inputs.add(
            ExportPageInput(
              pageId: pageId,
              imagePath: path,
              rotationDegrees: 0,
            ),
          );
        }
        return inputs;

      case ImageFilePageSource(:final imagePath):
        final pageId = _uuid.v4();
        final sourceExt = p.extension(imagePath).replaceFirst('.', '');
        final ext = sourceExt.isEmpty ? 'jpg' : sourceExt;
        final path = _workingPaths.pagePathFor(sessionId, pageId, ext: ext);
        await File(imagePath).copy(path);
        return [
          ExportPageInput(pageId: pageId, imagePath: path, rotationDegrees: 0),
        ];
    }
  }
}
