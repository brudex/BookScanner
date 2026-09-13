import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Letterboxed destination for a camera preview of [aspectRatio] inside
/// [parent], matching `BoxFit.contain` (never stretch).
Rect fittedPreviewRect(Size parent, double aspectRatio) {
  if (parent.isEmpty || aspectRatio <= 0) {
    return Offset.zero & parent;
  }
  final parentAspect = parent.width / parent.height;
  late final Size child;
  if (parentAspect > aspectRatio) {
    final height = parent.height;
    child = Size(height * aspectRatio, height);
  } else {
    final width = parent.width;
    child = Size(width, width / aspectRatio);
  }
  final origin = Offset(
    (parent.width - child.width) / 2,
    (parent.height - child.height) / 2,
  );
  return origin & child;
}

/// Maps a tap in parent coordinates into the 0-1 preview space, or null
/// when the tap lands in the letterbox.
Offset? previewNormalizedPoint(Size parent, double aspectRatio, Offset local) {
  final rect = fittedPreviewRect(parent, aspectRatio);
  if (!rect.contains(local) || rect.width <= 0 || rect.height <= 0) {
    return null;
  }
  return Offset(
    ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
    ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
  );
}

/// Sensor/display rotation applied to a normalized analysis point so the
/// overlay matches an upright preview. Native ViewPort mapping should
/// already be identity; this remains for unit coverage of 0/90/180/270.
Offset rotateNormalized(Offset p, int rotationDegrees) {
  final turns = ((rotationDegrees % 360) + 360) % 360;
  return switch (turns) {
    90 => Offset(1 - p.dy, p.dx),
    180 => Offset(1 - p.dx, 1 - p.dy),
    270 => Offset(p.dy, 1 - p.dx),
    _ => p,
  };
}

double clampedAspectRatio(double value) => math.max(value, 0.01);
