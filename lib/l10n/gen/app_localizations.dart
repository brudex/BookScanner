import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title shown in the OS app switcher
  ///
  /// In en, this message translates to:
  /// **'BookScanner'**
  String get appTitle;

  /// Title of the main library screen
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// Shown when the library has no projects
  ///
  /// In en, this message translates to:
  /// **'No scans yet'**
  String get libraryEmptyTitle;

  /// Subtitle under the empty library state
  ///
  /// In en, this message translates to:
  /// **'Tap New Scan to digitize your first document or book'**
  String get libraryEmptySubtitle;

  /// Button that starts a new scan
  ///
  /// In en, this message translates to:
  /// **'New Scan'**
  String get newScan;

  /// Placeholder text for the library search field
  ///
  /// In en, this message translates to:
  /// **'Search by name or text'**
  String get searchHint;

  /// Section header for folders
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// Section header for favorite projects
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// Section header for the trash/recovery area
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// Number of pages in a project
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pages} =1{1 page} other{{count} pages}}'**
  String pageCount(num count);

  /// Title of the capture-mode picker sheet
  ///
  /// In en, this message translates to:
  /// **'What are you scanning?'**
  String get newScanModeTitle;

  /// Document capture mode
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get modeDocument;

  /// Subtitle for document capture mode
  ///
  /// In en, this message translates to:
  /// **'Single or multi-page documents, receipts, IDs'**
  String get modeDocumentSubtitle;

  /// Book capture mode
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get modeBook;

  /// Subtitle for book capture mode
  ///
  /// In en, this message translates to:
  /// **'Bound books with page-turn guidance and dewarping'**
  String get modeBookSubtitle;

  /// Title of the capture screen
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get captureTitle;

  /// Label for automatic capture toggle
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get captureAutoLabel;

  /// Explains why camera permission is requested
  ///
  /// In en, this message translates to:
  /// **'BookScanner needs camera access to scan documents. Nothing is uploaded — scanning works fully offline.'**
  String get capturePermissionRationale;

  /// Shown after camera permission is denied
  ///
  /// In en, this message translates to:
  /// **'Camera access was denied. Enable it in system settings to scan.'**
  String get capturePermissionDenied;

  /// Button to open OS app settings
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Live capture warning: blur
  ///
  /// In en, this message translates to:
  /// **'Hold steady — image is blurry'**
  String get captureWarningBlur;

  /// Live capture warning: glare
  ///
  /// In en, this message translates to:
  /// **'Reduce glare on the page'**
  String get captureWarningGlare;

  /// Live capture warning: low light
  ///
  /// In en, this message translates to:
  /// **'Low light — move to a brighter area'**
  String get captureWarningLowLight;

  /// Live capture warning: clipped edges
  ///
  /// In en, this message translates to:
  /// **'Page edges are cut off'**
  String get captureWarningClippedEdges;

  /// Live capture warning: skew
  ///
  /// In en, this message translates to:
  /// **'Straighten the page'**
  String get captureWarningSevereSkew;

  /// Live capture warning: finger occlusion
  ///
  /// In en, this message translates to:
  /// **'Fingers are covering the page'**
  String get captureWarningFinger;

  /// Override the quality gate and take the photo
  ///
  /// In en, this message translates to:
  /// **'Capture anyway'**
  String get captureAnyway;

  /// Shown while autofocus has not yet converged
  ///
  /// In en, this message translates to:
  /// **'Focusing…'**
  String get captureFocusing;

  /// Shown when the camera detects motion
  ///
  /// In en, this message translates to:
  /// **'Hold still'**
  String get captureHoldStill;

  /// Flash mode: off
  ///
  /// In en, this message translates to:
  /// **'Flash off'**
  String get captureFlashOff;

  /// Flash mode: on
  ///
  /// In en, this message translates to:
  /// **'Flash on'**
  String get captureFlashOn;

  /// Flash mode: auto
  ///
  /// In en, this message translates to:
  /// **'Flash auto'**
  String get captureFlashAuto;

  /// Flash mode: torch
  ///
  /// In en, this message translates to:
  /// **'Torch'**
  String get captureTorch;

  /// Semantic label for the capture zoom slider
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get captureZoom;

  /// Running count of pages captured in the current session
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pages yet} =1{1 page scanned} other{{count} pages scanned}}'**
  String pagesScanned(num count);

  /// Finish the capture session and go to review
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneScanning;

  /// Page count subtitle on a project row in the library list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pages} =1{1 page} other{{count} pages}}'**
  String projectPageCount(num count);

  /// Tooltip/semantic label for a project row's context-menu button
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get projectRowMenu;

  /// Title of the page review grid
  ///
  /// In en, this message translates to:
  /// **'Review pages'**
  String get reviewTitle;

  /// Switches Page Review between list and grid layouts
  ///
  /// In en, this message translates to:
  /// **'Toggle grid/list view'**
  String get toggleGridView;

  /// Action to rescan a flagged page
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get rescan;

  /// Rotate a page
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get rotate;

  /// Duplicate a page
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// Delete a page
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Warning badge for a likely duplicate page
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate'**
  String get possibleDuplicate;

  /// Warning badge for a likely gap in page sequence
  ///
  /// In en, this message translates to:
  /// **'Possible missing page before this one'**
  String get possibleMissingPage;

  /// Warning badge for a low quality-score page
  ///
  /// In en, this message translates to:
  /// **'Low quality — consider rescanning'**
  String get lowQuality;

  /// Menu action to open manual crop correction
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropAction;

  /// Menu action to open the filter/brightness/contrast/sharpness adjustment screen
  ///
  /// In en, this message translates to:
  /// **'Filter & adjust'**
  String get adjustAction;

  /// Title of the filter/brightness/contrast/sharpness adjustment screen
  ///
  /// In en, this message translates to:
  /// **'Filter & adjust'**
  String get adjustTitle;

  /// PageFilter.original display name
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get filterOriginal;

  /// PageFilter.enhancedColor display name
  ///
  /// In en, this message translates to:
  /// **'Enhanced'**
  String get filterEnhancedColor;

  /// PageFilter.grayscale display name
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get filterGrayscale;

  /// PageFilter.blackAndWhite display name
  ///
  /// In en, this message translates to:
  /// **'Black & White'**
  String get filterBlackAndWhite;

  /// PageFilter.photo display name
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get filterPhoto;

  /// Brightness slider label
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightnessLabel;

  /// Contrast slider label
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrastLabel;

  /// Sharpness slider label
  ///
  /// In en, this message translates to:
  /// **'Sharpness'**
  String get sharpnessLabel;

  /// Menu action to open manual book-spread split correction, only shown for pages from a split spread
  ///
  /// In en, this message translates to:
  /// **'Re-split spread'**
  String get spreadSplitAction;

  /// Title of the manual book-spread split correction screen
  ///
  /// In en, this message translates to:
  /// **'Adjust spread split'**
  String get spreadSplitTitle;

  /// Title of the manual four-corner crop correction screen
  ///
  /// In en, this message translates to:
  /// **'Adjust corners'**
  String get cropTitle;

  /// Re-run automatic edge detection on the crop screen
  ///
  /// In en, this message translates to:
  /// **'Auto-detect edges'**
  String get cropAutoDetect;

  /// Reset the crop quad to the entire image
  ///
  /// In en, this message translates to:
  /// **'Reset to full frame'**
  String get cropResetFullFrame;

  /// Menu action to open the OCR review screen
  ///
  /// In en, this message translates to:
  /// **'Recognize text'**
  String get ocrAction;

  /// Title of the OCR review/correction screen
  ///
  /// In en, this message translates to:
  /// **'Recognized text'**
  String get ocrReviewTitle;

  /// Shown before OCR has ever run for a page
  ///
  /// In en, this message translates to:
  /// **'OCR has not been run for this page yet'**
  String get ocrEmptyTitle;

  /// Shown after OCR ran but recognized zero text blocks
  ///
  /// In en, this message translates to:
  /// **'No text was found on this page'**
  String get ocrNoTextFound;

  /// Button to run OCR for the first time
  ///
  /// In en, this message translates to:
  /// **'Recognize text'**
  String get ocrRunButton;

  /// Button to force re-run OCR on an already-processed page
  ///
  /// In en, this message translates to:
  /// **'Re-run OCR'**
  String get ocrRerunButton;

  /// Shown while OCR is running
  ///
  /// In en, this message translates to:
  /// **'Recognizing text…'**
  String get ocrRunningLabel;

  /// Badge shown on a low-confidence recognized block
  ///
  /// In en, this message translates to:
  /// **'Low confidence — tap to correct'**
  String get ocrLowConfidenceLabel;

  /// Badge shown on a block the user has corrected
  ///
  /// In en, this message translates to:
  /// **'Corrected'**
  String get ocrCorrectedLabel;

  /// Title of the block text-correction dialog
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get ocrEditBlockTitle;

  /// Title of the export screen
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportTitle;

  /// Export format option
  ///
  /// In en, this message translates to:
  /// **'Image-only PDF'**
  String get exportImagePdf;

  /// Export format option
  ///
  /// In en, this message translates to:
  /// **'Searchable PDF'**
  String get exportSearchablePdf;

  /// Export format option
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get exportMarkdown;

  /// Export format option
  ///
  /// In en, this message translates to:
  /// **'Word (.docx)'**
  String get exportDocx;

  /// Export progress label
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get exportInProgress;

  /// Export finished label
  ///
  /// In en, this message translates to:
  /// **'Export complete'**
  String get exportComplete;

  /// Export failed label
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// Share the exported file
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Confirmation before exporting a very large book
  ///
  /// In en, this message translates to:
  /// **'This book has {count} pages. Exporting may take a while. Continue?'**
  String largeExportAcknowledgement(num count);

  /// Action opening the multi-source page-composition screen from Export
  ///
  /// In en, this message translates to:
  /// **'Merge / edit pages'**
  String get composeDocumentAction;

  /// Title of the multi-source page-composition screen
  ///
  /// In en, this message translates to:
  /// **'Edit pages'**
  String get composeTitle;

  /// Action opening the source picker to merge in more pages
  ///
  /// In en, this message translates to:
  /// **'Add pages'**
  String get composeAddPagesAction;

  /// Toggles extract-selection mode on the composition screen
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get composeSelectForExtractAction;

  /// Exports only the selected pages as a new PDF
  ///
  /// In en, this message translates to:
  /// **'Extract'**
  String get composeExtractAction;

  /// Exports the whole composed document (or each split group) as PDF
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get composeExportAction;

  /// Opens the source picker to insert pages before this one
  ///
  /// In en, this message translates to:
  /// **'Insert before…'**
  String get composeInsertBeforeAction;

  /// Opens the source picker to replace this page
  ///
  /// In en, this message translates to:
  /// **'Replace…'**
  String get composeReplaceAction;

  /// Toggles a split marker after this page
  ///
  /// In en, this message translates to:
  /// **'Split after this page'**
  String get composeSplitAfterAction;

  /// Removes a split marker after this page
  ///
  /// In en, this message translates to:
  /// **'Remove split marker'**
  String get composeRemoveSplitAfterAction;

  /// Source-picker option: merge in another BookScanner project's pages
  ///
  /// In en, this message translates to:
  /// **'From another project'**
  String get composeSourceFromProject;

  /// Source-picker option: import pages from an existing PDF file
  ///
  /// In en, this message translates to:
  /// **'From a PDF file'**
  String get composeSourceFromPdf;

  /// Source-picker option: insert a single picked image as a page
  ///
  /// In en, this message translates to:
  /// **'From an image'**
  String get composeSourceFromImage;

  /// Progress label while exporting a split document's multiple output files
  ///
  /// In en, this message translates to:
  /// **'Exporting {current} of {total}…'**
  String composeExportingJobOfTotal(num current, num total);

  /// Warning that some pages in the working document (typically imported ones) have no OCR text, so a searchable export won't cover them
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} pages have no recognized text yet'**
  String composePagesMissingOcrWarning(num count, num total);

  /// Title of the results view after a split export produces multiple PDFs
  ///
  /// In en, this message translates to:
  /// **'Split into {count} files'**
  String composeSplitResultsTitle(num count);

  /// Title of the settings screen
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Toggle for biometric/PIN app lock
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLock;

  /// Section for cloud OCR consent
  ///
  /// In en, this message translates to:
  /// **'Cloud processing'**
  String get settingsCloudProcessing;

  /// Setting for document OCR languages
  ///
  /// In en, this message translates to:
  /// **'OCR languages'**
  String get settingsOcrLanguages;

  /// Toggle to strip GPS metadata on export
  ///
  /// In en, this message translates to:
  /// **'Strip location from exports'**
  String get settingsStripLocation;

  /// Title of the copyright/responsible-use onboarding notice
  ///
  /// In en, this message translates to:
  /// **'Scan responsibly'**
  String get copyrightNoticeTitle;

  /// Body text of the copyright/responsible-use onboarding notice
  ///
  /// In en, this message translates to:
  /// **'Only scan content you own, that is in the public domain, or that you are authorized to reproduce. BookScanner does not support piracy or unauthorized redistribution.'**
  String get copyrightNoticeBody;

  /// Acknowledge button for the copyright notice
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get iUnderstand;

  /// Title of the cloud OCR consent dialog
  ///
  /// In en, this message translates to:
  /// **'Cloud processing consent'**
  String get cloudConsentTitle;

  /// Body of the cloud OCR consent dialog
  ///
  /// In en, this message translates to:
  /// **'This will upload the page image to a cloud service for higher-accuracy processing. On-device processing never leaves your phone.'**
  String get cloudConsentBody;

  /// Consent affirmative action
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// Consent decline action
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// Generic cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic retry action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic save action
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic close action
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Title of the dialog shown after finishing a capture session, prompting the user to name the project
  ///
  /// In en, this message translates to:
  /// **'Name this scan'**
  String get nameScanTitle;

  /// Text field label in the name-this-scan dialog
  ///
  /// In en, this message translates to:
  /// **'Scan name'**
  String get nameScanLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
