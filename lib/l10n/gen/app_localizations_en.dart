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
  String get libraryTitle => 'BookScanner';

  @override
  String get libraryEmptyTitle => 'No scans yet';

  @override
  String get libraryEmptySubtitle =>
      'Tap Scan Document or the camera to digitize your first page';

  @override
  String get newScan => 'New Scan';

  @override
  String get homeGreetingMorning => 'Good morning';

  @override
  String get homeGreetingAfternoon => 'Good afternoon';

  @override
  String get homeGreetingEvening => 'Good evening';

  @override
  String get homeQuickActions => 'Quick Actions';

  @override
  String get homeScanId => 'Scan ID';

  @override
  String get homeAddFolder => 'Add Folder';

  @override
  String get homeStatDocuments => 'Documents';

  @override
  String get homeStatBooks => 'Books';

  @override
  String get homeStatPages => 'Pages';

  @override
  String get homeActionDocumentScan => 'Document scan';

  @override
  String get homeActionBookScan => 'Book scan';

  @override
  String get homeActionImport => 'Import';

  @override
  String get homeFilterAll => 'All';

  @override
  String get homeNavHome => 'Home';

  @override
  String get homeNavScan => 'Scan';

  @override
  String get homeNavScans => 'Scans';

  @override
  String homeLibraryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scans in your library',
      one: '1 scan in your library',
      zero: 'No scans in your library',
    );
    return '$_temp0';
  }

  @override
  String get homeScanSection => 'Scan';

  @override
  String get homeScanDoc => 'Scan Document';

  @override
  String get homeScanDocSubtitle => 'Camera capture';

  @override
  String get homeScanBook => 'Scan Book';

  @override
  String get homeGallery => 'Gallery';

  @override
  String get homeGallerySubtitle => 'Photos from your roll';

  @override
  String get homeImportFile => 'Import';

  @override
  String get homeImportFileSubtitle => 'PDF into a new scan';

  @override
  String get homeBookSubtitle => 'Spreads & dewarp';

  @override
  String get homeFavoritesFilter => 'Favorites';

  @override
  String get rename => 'Rename';

  @override
  String get homePopularTools => 'Popular Tools';

  @override
  String get homeScanNow => 'Scan Now';

  @override
  String get homeRecent => 'Recent';

  @override
  String get homeImporting => 'Importing…';

  @override
  String get searchHint => 'Search scans…';

  @override
  String get scansSearchTitle => 'Scans';

  @override
  String get searchNoResults => 'No matching scans';

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
  String get sortAction => 'Sort';

  @override
  String get sortByDateUpdated => 'Date updated';

  @override
  String get sortByDateCreated => 'Date created';

  @override
  String get sortByTitle => 'Title';

  @override
  String get sortByPageCount => 'Page count';

  @override
  String get viewAsGrid => 'Grid view';

  @override
  String get viewAsList => 'List view';

  @override
  String get foldersEmptyTitle => 'No folders yet';

  @override
  String get createFolder => 'New folder';

  @override
  String get folderNameLabel => 'Folder name';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String get noFolder => 'No folder';

  @override
  String get editTags => 'Edit tags';

  @override
  String get tagsFieldLabel => 'Tags (comma separated)';

  @override
  String get batchRename => 'Rename selected';

  @override
  String get batchRenamePatternLabel => 'Name pattern (use # for the number)';

  @override
  String selectedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scans selected',
      one: '1 scan selected',
      zero: 'No scans selected',
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
  String get bookSetupTitle => 'Book details';

  @override
  String get bookSetupTitleField => 'Title';

  @override
  String get bookSetupAuthorField => 'Author';

  @override
  String get bookSetupLanguageField => 'Language';

  @override
  String get bookSetupStartingPageField => 'Starting page number';

  @override
  String get bookSetupEditionField => 'Edition';

  @override
  String get bookSetupIsbnField => 'ISBN';

  @override
  String get bookSetupTagsField => 'Tags (comma separated)';

  @override
  String get bookSetupNotesField => 'Notes';

  @override
  String get bookSetupScanMode => 'Scan mode';

  @override
  String get bookScanModeSinglePage => 'Single page';

  @override
  String get bookScanModeTwoPageSpread => 'Two-page spread';

  @override
  String get bookSetupPageOrder => 'Reading order';

  @override
  String get bookPageOrderLtr => 'Left to right';

  @override
  String get bookPageOrderRtl => 'Right to left';

  @override
  String get continueToCapture => 'Continue';

  @override
  String get captureTitle => 'Capture';

  @override
  String get captureAutoLabel => 'Auto';

  @override
  String get captureManualLabel => 'Manual';

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
  String get captureHoldStill => 'Hold the camera still';

  @override
  String get captureFlashOff => 'Flash off';

  @override
  String get captureImport => 'Import';

  @override
  String get captureGrid => 'Grid';

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
  String get doneScanning => 'Continue';

  @override
  String get postCaptureNext => 'Next';

  @override
  String get postCaptureSave => 'Save';

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
  String get reviewAddCamera => 'Camera';

  @override
  String get reviewAddGallery => 'Gallery';

  @override
  String get reviewAddFromFiles => 'Import from Files';

  @override
  String get reviewAddPagesTooltip => 'Add pages';

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
  String get dismissWarning => 'Dismiss';

  @override
  String get pdfOptionsSection => 'PDF options';

  @override
  String get pdfPageSize => 'Page size';

  @override
  String get pdfOrientation => 'Orientation';

  @override
  String get pdfMargins => 'Margins';

  @override
  String get pdfMarginsNone => 'None';

  @override
  String get pdfMarginsNarrow => 'Narrow';

  @override
  String get pdfMarginsNormal => 'Normal';

  @override
  String get pdfWatermark => 'Watermark';

  @override
  String get pdfWatermarkHint => 'Optional text overlay';

  @override
  String get pdfPageSizeA4 => 'A4';

  @override
  String get pdfPageSizeLetter => 'Letter';

  @override
  String get pdfPageSizeLegal => 'Legal';

  @override
  String get pdfPageSizeMatchSource => 'Match page';

  @override
  String get pdfOrientationPortrait => 'Portrait';

  @override
  String get pdfOrientationLandscape => 'Landscape';

  @override
  String get pdfOrientationAuto => 'Auto';

  @override
  String get printAction => 'Print';

  @override
  String get saveAsAction => 'Save as…';

  @override
  String get ocrLanguageEnglish => 'English';

  @override
  String get ocrLanguageSpanish => 'Spanish';

  @override
  String get ocrLanguageFrench => 'French';

  @override
  String get ocrLanguageGerman => 'German';

  @override
  String get ocrLanguagePortuguese => 'Portuguese';

  @override
  String get ocrLanguageItalian => 'Italian';

  @override
  String get cropAction => 'Crop';

  @override
  String get pageLabelAction => 'Page number / label';

  @override
  String get pageLabelTitle => 'Page label';

  @override
  String get pageLabelHint => 'e.g. Cover, iii, 12';

  @override
  String get adjustAction => 'Filter & adjust';

  @override
  String get adjustTitle => 'Filter & adjust';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterEnhancedColor => 'Document';

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
  String get fineRotationLabel => 'Fine rotation';

  @override
  String get thresholdLabel => 'Threshold';

  @override
  String get revertToOriginal => 'Revert to original';

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
  String get cropNoCrop => 'No Crop';

  @override
  String get cropRotateLeft => 'Rotate L';

  @override
  String get cropRotateRight => 'Rotate R';

  @override
  String get cropNext => 'Next';

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
  String get exportImages => 'Images (JPG/PNG)';

  @override
  String get exportImagesFormatJpg => 'JPG';

  @override
  String get exportImagesFormatPng => 'PNG';

  @override
  String get compressAction => 'Compress';

  @override
  String get compressQualityLabel => 'Quality';

  @override
  String compressEstimatedSize(String size) {
    return 'Estimated size: $size';
  }

  @override
  String get apply => 'Apply';

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
  String get settingsCaptureSection => 'Capture';

  @override
  String get settingsCountdown => 'Capture countdown';

  @override
  String get settingsCountdownOff => 'Off';

  @override
  String get settingsContinuousCapture => 'Continuous capture';

  @override
  String get settingsHapticConfirmation => 'Haptic feedback on capture';

  @override
  String get settingsAudioConfirmation => 'Sound on capture';

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

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingScanTitle => 'Scan Documents in Seconds';

  @override
  String get onboardingScanBody =>
      'Turn any paper into a crisp, ready-to-share PDF — right from your camera.';

  @override
  String get onboardingBookTitle => 'Built for Books, Too';

  @override
  String get onboardingBookBody =>
      'Capture a full two-page spread and we\'ll automatically flatten curves and split the pages.';

  @override
  String get onboardingOrganizeTitle => 'Export & Stay Organized';

  @override
  String get onboardingOrganizeBody =>
      'Save as PDF or Word, recognize text with OCR, and keep every scan easy to find.';

  @override
  String get unlockTitle => 'BookScanner is locked';

  @override
  String get unlockSubtitle => 'Confirm it\'s you to continue';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get unlockFailed => 'Couldn\'t verify — try again';

  @override
  String get favoritesEmptyTitle => 'No favorites yet';

  @override
  String get favoritesEmptySubtitle => 'Tap the star on a scan to add it here';

  @override
  String get trashEmptyTitle => 'Trash is empty';

  @override
  String get trashEmptySubtitle =>
      'Deleted scans appear here so you can restore or remove them forever';

  @override
  String get restoreAction => 'Restore';

  @override
  String get deleteForeverAction => 'Delete Forever';

  @override
  String get deleteForeverConfirmTitle => 'Delete forever?';

  @override
  String deleteForeverConfirmBody(String title) {
    return 'This can\'t be undone. \"$title\" and its pages will be permanently deleted.';
  }

  @override
  String deleteForeverConfirmBodySelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This can\'t be undone. $count selected scans and their pages will be permanently deleted.',
      one:
          'This can\'t be undone. 1 selected scan and its pages will be permanently deleted.',
    );
    return '$_temp0';
  }
}
