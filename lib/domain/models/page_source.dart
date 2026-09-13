/// One source of pages to bring into a multi-source page-composition
/// session (SPEC 6.5 "editing": merge/insert/replace from elsewhere).
sealed class PageSource {
  const PageSource();
}

/// Another BookScanner project's own pages, in project order.
class ProjectPageSource extends PageSource {
  const ProjectPageSource(this.projectId);

  final String projectId;
}

/// Pages rasterized from an existing PDF file the user picked.
class ExternalPdfPageSource extends PageSource {
  const ExternalPdfPageSource(this.pdfPath, {this.pageIndices});

  final String pdfPath;

  /// 0-based indices into the source PDF; null means every page.
  final List<int>? pageIndices;
}

/// A single plain image file (JPEG/PNG) the user picked.
class ImageFilePageSource extends PageSource {
  const ImageFilePageSource(this.imagePath);

  final String imagePath;
}
