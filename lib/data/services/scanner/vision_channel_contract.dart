/// Path-based still vision channel. Live camera frames never cross this
/// boundary (SPEC 9.1 / BookScannerRevamp §5.4).
class VisionChannelContract {
  VisionChannelContract._();

  static const String methodChannelName = 'com.quizfactor.bookscanner/vision';
  static const String methodIsAvailable = 'isAvailable';
  static const String methodDetectStill = 'detectStill';
  static const String methodEnhanceStill = 'enhanceStill';
  static const String methodScoreStill = 'scoreStill';
}
