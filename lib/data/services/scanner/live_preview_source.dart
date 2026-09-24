import 'package:flutter/widgets.dart';

/// Optional live preview surface from a capture adapter that owns a Flutter
/// camera plugin controller. Feature views use this instead of a raw
/// `Texture` id so the plugin can apply its own rotation/crop.
abstract interface class LivePreviewSource {
  Widget? buildLivePreview();
}
