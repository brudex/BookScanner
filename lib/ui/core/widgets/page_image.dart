import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Page images are camera/scanner photos that can be tens of megapixels.
/// Decoding one at full size costs 150-260 MB and froze Review (ANR), so
/// every page image in the UI decodes at about its on-screen size instead.
/// Decode widths are rounded up to a few buckets so a page shown at similar
/// sizes shares one cache entry.
const List<int> _decodeBuckets = [256, 512, 1024, 2048];

int _bucketFor(double physicalWidth) {
  for (final bucket in _decodeBuckets) {
    if (physicalWidth <= bucket) return bucket;
  }
  return _decodeBuckets.last;
}

/// Image provider for [path] decoded to at most [decodeWidth] physical
/// pixels wide (rounded up to a bucket). Never upscales a small image.
///
/// Crop, filters and revert rewrite page files in place, so the cache key
/// includes the file's modification time: a rewritten file always shows its
/// new pixels without every editor having to evict each cached size.
ImageProvider pageImageProvider(String path, {required double decodeWidth}) {
  final file = File(path);
  int stamp;
  try {
    stamp = file.lastModifiedSync().microsecondsSinceEpoch;
  } on FileSystemException {
    stamp = 0;
  }
  return ResizeImage(
    _StampedFileImage(file, stamp),
    width: _bucketFor(decodeWidth),
    policy: ResizeImagePolicy.fit,
  );
}

class _StampedFileImage extends FileImage {
  const _StampedFileImage(super.file, this.stamp);

  final int stamp;

  @override
  bool operator ==(Object other) =>
      other is _StampedFileImage &&
      other.file.path == file.path &&
      other.stamp == stamp &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(file.path, stamp, scale);
}

/// Pixel size of the image at [path], read from its header without
/// decoding the pixels.
Future<ui.Size> readImageSize(String path) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(path).readAsBytes(),
  );
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = ui.Size(
    descriptor.width.toDouble(),
    descriptor.height.toDouble(),
  );
  descriptor.dispose();
  buffer.dispose();
  return size;
}

/// A page image decoded at its laid-out size. [zoom] raises the decode
/// width for views that can be pinch-zoomed.
class PageImage extends StatelessWidget {
  const PageImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.zoom = 1,
    this.gaplessPlayback = true,
    this.color,
    this.colorBlendMode,
    this.errorBuilder,
  });

  final String path;
  final BoxFit fit;
  final double zoom;
  final bool gaplessPlayback;
  final Color? color;
  final BlendMode? colorBlendMode;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cover/fill can crop or stretch, so size by the larger side.
        final logical = math.max(
          constraints.hasBoundedWidth ? constraints.maxWidth : 0.0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 0.0,
        );
        final width = logical > 0 ? logical * dpr * zoom : 1024.0;
        return Image(
          image: pageImageProvider(path, decodeWidth: width),
          fit: fit,
          gaplessPlayback: gaplessPlayback,
          color: color,
          colorBlendMode: colorBlendMode,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
