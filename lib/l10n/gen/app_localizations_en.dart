// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BookScanner';

  @override
  String get libraryTitle => 'Library';

  @override
  String get libraryEmptyTitle => 'No scans yet';

  @override
  String get libraryEmptySubtitle =>
      'Tap New Scan to digitize your first document or book';

  @override
  String get newScan => 'New Scan';

  @override
  String get searchHint => 'Search by name or text';

  @override
  String get folders => 'Folders';

  @override
  String get favorites => 'Favorites';

  @override
  String get trash => 'Trash';

  @override
  String pageCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
      zero: 'No pages',
    );
    return '$_temp0';
  }

  @override
  String get newScanModeTitle => 'What are you scanning?';

  @override
  String get modeDocument => 'Document';

  @override
  String get modeDocumentSubtitle =>
      'Single or multi-page documents, receipts, IDs';

  @override
  String get modeBook => 'Book';

  @override
  String get modeBookSubtitle =>
      'Bound books with page-turn guidance and dewarping';

  @override
  String get captureTitle => 'Capture';

  @override
  String get captureAutoLabel => 'Auto';

  @override
  String get capturePermissionRationale =>
      'BookScanner needs camera access to scan documents. Nothing is uploaded — scanning works fully offline.';

  @override
  String get capturePermissionDenied =>
      'Camera access was denied. Enable it in system settings to scan.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get captureWarningBlur => 'Hold steady — image is blurry';

  @override
  String get captureWarningGlare => 'Reduce glare on the page';

  @override
  String get captureWarningLowLight => 'Low light — move to a brighter area';

  @override
  String get captureWarningClippedEdges => 'Page edges are cut off';

  @override
  String get captureWarningSevereSkew => 'Straighten the page';

  @override
  String get captureWarningFinger => 'Fingers are covering the page';

  @override
  String get captureAnyway => 'Capture anyway';

  @override
  String get captureFocusing => 'Focusing…';

  @override
  String get captureHoldStill => 'Hold still';

  @override
  String get captureFlashOff => 'Flash off';

  @override
  String get captureFlashOn => 'Flash on';

  @override
  String get captureFlashAuto => 'Flash auto';

  @override
  String get captureTorch => 'Torch';

  @override
  String get captureZoom => 'Zoom';

  @override
  String pagesScanned(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages scanned',
      one: '1 page scanned',
      zero: 'No pages yet',
    );
    return '$_temp0';
  }

  @override
  String get doneScanning => 'Done';

  @override
  String projectPageCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
      zero: 'No pages',
    );
    return '$_temp0';
  }

  @override
  String get projectRowMenu => 'More options';

  @override
  String get reviewTitle => 'Review pages';

  @override
  String get toggleGridView => 'Toggle grid/list view';

  @override
  String get rescan => 'Rescan';

  @override
  String get rotate => 'Rotate';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get delete => 'Delete';

  @override
  String get possibleDuplicate => 'Possible duplicate';

  @override
  String get possibleMissingPage => 'Possible missing page before this one';

  @override
  String get lowQuality => 'Low quality — consider rescanning';

  @override
  String get cropAction => 'Crop';

  @override
  String get adjustAction => 'Filter & adjust';

  @override
  String get adjustTitle => 'Filter & adjust';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterEnhancedColor => 'Enhanced';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get filterBlackAndWhite => 'Black & White';

  @override
  String get filterPhoto => 'Photo';

  @override
  String get brightnessLabel => 'Brightness';

  @override
  String get contrastLabel => 'Contrast';

  @override
  String get sharpnessLabel => 'Sharpness';

  @override
  String get spreadSplitAction => 'Re-split spread';

  @override
  String get spreadSplitTitle => 'Adjust spread split';

  @override
  String get cropTitle => 'Adjust corners';

  @override
  String get cropAutoDetect => 'Auto-detect edges';

  @override
  String get cropResetFullFrame => 'Reset to full frame';

  @override
  String get ocrAction => 'Recognize text';

  @override
  String get ocrReviewTitle => 'Recognized text';

  @override
  String get ocrEmptyTitle => 'OCR has not been run for this page yet';

  @override
  String get ocrNoTextFound => 'No text was found on this page';

  @override
  String get ocrRunButton => 'Recognize text';

  @override
  String get ocrRerunButton => 'Re-run OCR';

  @override
  String get ocrRunningLabel => 'Recognizing text…';

  @override
  String get ocrLowConfidenceLabel => 'Low confidence — tap to correct';

  @override
  String get ocrCorrectedLabel => 'Corrected';

  @override
  String get ocrEditBlockTitle => 'Edit text';

  @override
  String get exportTitle => 'Export';

  @override
  String get exportImagePdf => 'Image-only PDF';

  @override
  String get exportSearchablePdf => 'Searchable PDF';

  @override
  String get exportMarkdown => 'Markdown';

  @override
  String get exportDocx => 'Word (.docx)';

  @override
  String get exportInProgress => 'Exporting…';

  @override
  String get exportComplete => 'Export complete';

  @override
  String get exportFailed => 'Export failed';

  @override
  String get share => 'Share';

  @override
  String largeExportAcknowledgement(num count) {
    return 'This book has $count pages. Exporting may take a while. Continue?';
  }

  @override
  String get composeDocumentAction => 'Merge / edit pages';

  @override
  String get composeTitle => 'Edit pages';

  @override
  String get composeAddPagesAction => 'Add pages';

  @override
  String get composeSelectForExtractAction => 'Select';

  @override
  String get composeExtractAction => 'Extract';

  @override
  String get composeExportAction => 'Export';

  @override
  String get composeInsertBeforeAction => 'Insert before…';

  @override
  String get composeReplaceAction => 'Replace…';

  @override
  String get composeSplitAfterAction => 'Split after this page';

  @override
  String get composeRemoveSplitAfterAction => 'Remove split marker';

  @override
  String get composeSourceFromProject => 'From another project';

  @override
  String get composeSourceFromPdf => 'From a PDF file';

  @override
  String get composeSourceFromImage => 'From an image';

  @override
  String composeExportingJobOfTotal(num current, num total) {
    return 'Exporting $current of $total…';
  }

  @override
  String composePagesMissingOcrWarning(num count, num total) {
    return '$count of $total pages have no recognized text yet';
  }

  @override
  String composeSplitResultsTitle(num count) {
    return 'Split into $count files';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppLock => 'App lock';

  @override
  String get settingsCloudProcessing => 'Cloud processing';

  @override
  String get settingsOcrLanguages => 'OCR languages';

  @override
  String get settingsStripLocation => 'Strip location from exports';

  @override
  String get copyrightNoticeTitle => 'Scan responsibly';

  @override
  String get copyrightNoticeBody =>
      'Only scan content you own, that is in the public domain, or that you are authorized to reproduce. BookScanner does not support piracy or unauthorized redistribution.';

  @override
  String get iUnderstand => 'I understand';

  @override
  String get cloudConsentTitle => 'Cloud processing consent';

  @override
  String get cloudConsentBody =>
      'This will upload the page image to a cloud service for higher-accuracy processing. On-device processing never leaves your phone.';

  @override
  String get allow => 'Allow';

  @override
  String get notNow => 'Not now';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get nameScanTitle => 'Name this scan';

  @override
  String get nameScanLabel => 'Scan name';
}
