/// Domain-facing abstraction over on-disk path allocation, implemented by
/// the data layer's `AppPaths`. Keeps use cases from depending on a
/// concrete file-storage Service directly (SPEC 9.1 layering).
abstract interface class PagePathAllocator {
  String originalPathFor(String pageId, {required String ext});
  String processedPathFor(String pageId, {required String ext});
  String thumbnailPathFor(String pageId);
  String exportPathFor(String jobId, String extension);
}
