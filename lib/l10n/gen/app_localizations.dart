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

  /// Title of the main home hub
  ///
  /// In en, this message translates to:
  /// **'BookScanner'**
  String get libraryTitle;

  /// Shown when the library has no projects
  ///
  /// In en, this message translates to:
  /// **'No scans yet'**
  String get libraryEmptyTitle;

  /// Subtitle under the empty library state
  ///
  /// In en, this message translates to:
  /// **'Tap Scan Document or the camera to digitize your first page'**
  String get libraryEmptySubtitle;

  /// Button that starts a new scan
  ///
  /// In en, this message translates to:
  /// **'New Scan'**
  String get newScan;

  /// Home greeting before noon
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGreetingMorning;

  /// Home greeting from noon until evening
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGreetingAfternoon;

  /// Home greeting after 5pm
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGreetingEvening;

  /// Section header above the horizontal quick-action tools
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get homeQuickActions;

  /// Quick action that starts an ID-card capture
  ///
  /// In en, this message translates to:
  /// **'Scan ID'**
  String get homeScanId;

  /// Quick action that opens folder creation
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get homeAddFolder;

  /// Home filter chip / label for document projects
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get homeStatDocuments;

  /// Home filter chip / label for book projects
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get homeStatBooks;

  /// Home stat label for total captured pages (legacy)
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get homeStatPages;

  /// Home hero card that opens document capture
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get homeActionDocumentScan;

  /// Subtitle under the Document hero card
  ///
  /// In en, this message translates to:
  /// **'Single or multiple pages'**
  String get homeActionDocumentScanSubtitle;

  /// Home hero card that opens book capture
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get homeActionBookScan;

  /// Subtitle under the Book hero card
  ///
  /// In en, this message translates to:
  /// **'Scan pages as book'**
  String get homeActionBookScanSubtitle;

  /// Home hero card that opens ID-card capture
  ///
  /// In en, this message translates to:
  /// **'ID Card'**
  String get homeActionIdScan;

  /// Subtitle under the ID Card hero card
  ///
  /// In en, this message translates to:
  /// **'Passport, ID, license'**
  String get homeActionIdScanSubtitle;

  /// Home quick-start tile that imports from the gallery
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get homeActionImport;

  /// Library chip that shows every scan
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get homeFilterAll;

  /// Bottom dock label for the library
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeNavHome;

  /// Bottom dock label for document capture
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get homeNavScan;

  /// Bottom dock label that opens the full scan list
  ///
  /// In en, this message translates to:
  /// **'Scans'**
  String get homeNavScans;

  /// Muted count under the Recents header
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No scans in your library} =1{1 scan in your library} other{{count} scans in your library}}'**
  String homeLibraryCount(num count);

  /// Home section label above scan action cards
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get homeScanSection;

  /// Home card that starts a document capture
  ///
  /// In en, this message translates to:
  /// **'Scan Document'**
  String get homeScanDoc;

  /// Subtitle under the Scan hub card
  ///
  /// In en, this message translates to:
  /// **'Camera capture'**
  String get homeScanDocSubtitle;

  /// Home card that starts a book capture
  ///
  /// In en, this message translates to:
  /// **'Scan Book'**
  String get homeScanBook;

  /// Home card that imports photos
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get homeGallery;

  /// Subtitle under the Gallery hub card
  ///
  /// In en, this message translates to:
  /// **'Photos from your roll'**
  String get homeGallerySubtitle;

  /// Home card that imports a PDF
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get homeImportFile;

  /// Subtitle under the Import hub card
  ///
  /// In en, this message translates to:
  /// **'PDF into a new scan'**
  String get homeImportFileSubtitle;

  /// Subtitle under the Book hub card
  ///
  /// In en, this message translates to:
  /// **'Spreads & dewarp'**
  String get homeBookSubtitle;

  /// Toggle showing only favorite scans
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get homeFavoritesFilter;

  /// Rename a scan from the home list
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Home section label for shortcut tools
  ///
  /// In en, this message translates to:
  /// **'Popular Tools'**
  String get homePopularTools;

  /// Callout above the new-scan button
  ///
  /// In en, this message translates to:
  /// **'Scan Now'**
  String get homeScanNow;

  /// Section header for recent scans
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get homeRecent;

  /// Shown while gallery or PDF import is running
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get homeImporting;

  /// Placeholder text for the library search field
  ///
  /// In en, this message translates to:
  /// **'Search scans…'**
  String get searchHint;

  /// Title of the full-library search screen opened from Home
  ///
  /// In en, this message translates to:
  /// **'Scans'**
  String get scansSearchTitle;

  /// Shown on the scans search screen when the query matches nothing
  ///
  /// In en, this message translates to:
  /// **'No matching scans'**
  String get searchNoResults;

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

  /// Opens the library sort-order menu
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortAction;

  /// Sort option: most recently updated first
  ///
  /// In en, this message translates to:
  /// **'Date updated'**
  String get sortByDateUpdated;

  /// Sort option: most recently created first
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get sortByDateCreated;

  /// Sort option: alphabetical by title
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortByTitle;

  /// Sort option: number of pages
  ///
  /// In en, this message translates to:
  /// **'Page count'**
  String get sortByPageCount;

  /// Switches the library list to a thumbnail grid
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get viewAsGrid;

  /// Switches the library grid back to a list
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get viewAsList;

  /// Shown when there are no folders
  ///
  /// In en, this message translates to:
  /// **'No folders yet'**
  String get foldersEmptyTitle;

  /// Action to create a new folder
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get createFolder;

  /// Text field label when naming a folder
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderNameLabel;

  /// Action to delete a folder
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// Action opening the folder picker for a project
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// Folder-picker option removing a project from any folder
  ///
  /// In en, this message translates to:
  /// **'No folder'**
  String get noFolder;

  /// Action opening the tag editor for a project
  ///
  /// In en, this message translates to:
  /// **'Edit tags'**
  String get editTags;

  /// Text field label in the tag editor dialog
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get tagsFieldLabel;

  /// Batch-renames every selected project with a numbered pattern
  ///
  /// In en, this message translates to:
  /// **'Rename selected'**
  String get batchRename;

  /// Text field label in the batch-rename dialog
  ///
  /// In en, this message translates to:
  /// **'Name pattern (use # for the number)'**
  String get batchRenamePatternLabel;

  /// Shown in the library selection action bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No scans selected} =1{1 scan selected} other{{count} scans selected}}'**
  String selectedCount(num count);

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
  /// **'Single or multi-page documents and receipts'**
  String get modeDocumentSubtitle;

  /// ID capture mode on the new-scan picker
  ///
  /// In en, this message translates to:
  /// **'Scan ID'**
  String get modeScanId;

  /// Subtitle for ID capture mode
  ///
  /// In en, this message translates to:
  /// **'Scan the front, then the back, then export'**
  String get modeScanIdSubtitle;

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

  /// Title of the optional book metadata screen before capture
  ///
  /// In en, this message translates to:
  /// **'Book details'**
  String get bookSetupTitle;

  /// Book title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get bookSetupTitleField;

  /// Book author field
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get bookSetupAuthorField;

  /// Book language field
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get bookSetupLanguageField;

  /// First printed page number in this scan session
  ///
  /// In en, this message translates to:
  /// **'Starting page number'**
  String get bookSetupStartingPageField;

  /// Book edition field
  ///
  /// In en, this message translates to:
  /// **'Edition'**
  String get bookSetupEditionField;

  /// Book ISBN field
  ///
  /// In en, this message translates to:
  /// **'ISBN'**
  String get bookSetupIsbnField;

  /// Book tags field, entered as a comma-separated list
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get bookSetupTagsField;

  /// Book notes field
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get bookSetupNotesField;

  /// Label for single-page vs two-page spread
  ///
  /// In en, this message translates to:
  /// **'Scan mode'**
  String get bookSetupScanMode;

  /// Photograph one book page at a time
  ///
  /// In en, this message translates to:
  /// **'Single page'**
  String get bookScanModeSinglePage;

  /// Photograph an open two-page spread
  ///
  /// In en, this message translates to:
  /// **'Two-page spread'**
  String get bookScanModeTwoPageSpread;

  /// Left-to-right or right-to-left page order
  ///
  /// In en, this message translates to:
  /// **'Reading order'**
  String get bookSetupPageOrder;

  /// LTR books
  ///
  /// In en, this message translates to:
  /// **'Left to right'**
  String get bookPageOrderLtr;

  /// RTL books
  ///
  /// In en, this message translates to:
  /// **'Right to left'**
  String get bookPageOrderRtl;

  /// Proceed from book setup to the camera
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueToCapture;

  /// Title of the capture screen
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get captureTitle;

  /// Label for automatic capture mode
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get captureAutoLabel;

  /// Label for manual shutter capture mode
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get captureManualLabel;

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
  /// **'Hold the camera still'**
  String get captureHoldStill;

  /// Flash mode: off
  ///
  /// In en, this message translates to:
  /// **'Flash off'**
  String get captureFlashOff;

  /// Add a page from the photo library during capture
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get captureImport;

  /// Title shown before the native scanner opens
  ///
  /// In en, this message translates to:
  /// **'Ready to scan'**
  String get captureReadyTitle;

  /// Title shown before book capture starts
  ///
  /// In en, this message translates to:
  /// **'Ready to scan your book'**
  String get captureReadyBookTitle;

  /// Explains that the start button opens the scanner
  ///
  /// In en, this message translates to:
  /// **'Start scanning opens the scanner. Take your pages there. When you come back, you\'ll crop each page, then set its filters.'**
  String get captureReadyBody;

  /// Explains fast book scanning before the camera opens
  ///
  /// In en, this message translates to:
  /// **'Photograph one page at a time. Keep scanning — pages process in the background. Tap Done when finished to open Review.'**
  String get captureReadyBookBody;

  /// Title of the continuous book capture camera screen
  ///
  /// In en, this message translates to:
  /// **'Book Scan'**
  String get bookScanTitle;

  /// Shown while pages returned by the system scanner are saved to the book
  ///
  /// In en, this message translates to:
  /// **'Saving pages…'**
  String get bookScanSaving;

  /// Reopens the system page scanner after it failed to start
  ///
  /// In en, this message translates to:
  /// **'Open scanner'**
  String get bookScanOpenScanner;

  /// Finish book capture and open Review after background processing
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get bookScanDone;

  /// Toggle automatic shutter during book scan
  ///
  /// In en, this message translates to:
  /// **'Auto capture'**
  String get bookAutoCapture;

  /// Guidance pill while lining up a book page
  ///
  /// In en, this message translates to:
  /// **'Hold steady to capture'**
  String get bookHoldSteady;

  /// Guidance pill when live edge detection finds a page
  ///
  /// In en, this message translates to:
  /// **'Page detected'**
  String get bookPageDetected;

  /// Lightweight toast after a book page is saved and queued for background enhance
  ///
  /// In en, this message translates to:
  /// **'Page {page} captured · Processing'**
  String bookPageCapturedProcessing(int page);

  /// Running page count on the book capture bottom bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 pages} =1{1 page} other{{count} pages}}'**
  String bookPagesCount(num count);

  /// Title of the in-session book pages sheet
  ///
  /// In en, this message translates to:
  /// **'Captured pages'**
  String get bookSessionPagesTitle;

  /// Closes the in-session pages sheet and returns to the live camera
  ///
  /// In en, this message translates to:
  /// **'Resume scanning'**
  String get bookResumeScanning;

  /// Button that opens the native document scanner
  ///
  /// In en, this message translates to:
  /// **'Start scanning'**
  String get captureStartScanning;

  /// Prompt before scanning the front of an ID
  ///
  /// In en, this message translates to:
  /// **'Scan the front'**
  String get scanIdFrontTitle;

  /// Explains the front-of-ID scan step
  ///
  /// In en, this message translates to:
  /// **'Open the scanner and photograph the front of the ID.'**
  String get scanIdFrontBody;

  /// Opens the scanner for the front of an ID
  ///
  /// In en, this message translates to:
  /// **'Scan front'**
  String get scanIdFrontButton;

  /// Prompt before scanning the back of an ID
  ///
  /// In en, this message translates to:
  /// **'Scan the back'**
  String get scanIdBackTitle;

  /// Explains the back-of-ID scan step
  ///
  /// In en, this message translates to:
  /// **'Photograph the back of the ID. You\'ll then review both sides and export.'**
  String get scanIdBackBody;

  /// Opens the scanner for the back of an ID
  ///
  /// In en, this message translates to:
  /// **'Scan back'**
  String get scanIdBackButton;

  /// Page label for the front of an ID
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get scanIdSideFront;

  /// Page label for the back of an ID
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get scanIdSideBack;

  /// Toggle the camera composition grid
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get captureGrid;

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

  /// Finish the capture session and open post-capture page editing
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get doneScanning;

  /// Save the current page look and open the next captured page
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get postCaptureNext;

  /// Save the last page look, then name the scan
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get postCaptureSave;

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

  /// Review bottom action: open the camera
  ///
  /// In en, this message translates to:
  /// **'Add from Camera'**
  String get reviewAddCamera;

  /// Review bottom action: pick photos from the gallery
  ///
  /// In en, this message translates to:
  /// **'Add from Gallery'**
  String get reviewAddGallery;

  /// Review bottom action: import a PDF from Files
  ///
  /// In en, this message translates to:
  /// **'Import Files'**
  String get reviewAddFromFiles;

  /// Full-width export button on Review pages
  ///
  /// In en, this message translates to:
  /// **'Export / Convert'**
  String get reviewExportConvert;

  /// Subtitle of the export format sheet
  ///
  /// In en, this message translates to:
  /// **'Choose a format to export your document'**
  String get reviewExportSheetSubtitle;

  /// Export sheet option for PDF
  ///
  /// In en, this message translates to:
  /// **'Export as PDF'**
  String get reviewExportPdf;

  /// Description under Export as PDF
  ///
  /// In en, this message translates to:
  /// **'Create a high-quality, searchable PDF with OCR text.'**
  String get reviewExportPdfHint;

  /// Export sheet option for Markdown
  ///
  /// In en, this message translates to:
  /// **'Export as Markdown'**
  String get reviewExportMarkdown;

  /// Description under Export as Markdown
  ///
  /// In en, this message translates to:
  /// **'Recognize text (OCR) and convert to clean Markdown with headings, tables and structure.'**
  String get reviewExportMarkdownHint;

  /// Export sheet option for EPUB
  ///
  /// In en, this message translates to:
  /// **'Export as EPUB'**
  String get reviewExportEpub;

  /// Description under Export as EPUB
  ///
  /// In en, this message translates to:
  /// **'Create a readable EPUB for eBook readers. Best for scanned books.'**
  String get reviewExportEpubHint;

  /// Section label for PDF-only export settings
  ///
  /// In en, this message translates to:
  /// **'PDF OPTIONS'**
  String get reviewExportPdfOptions;

  /// Section label for Markdown-only export settings
  ///
  /// In en, this message translates to:
  /// **'MARKDOWN OPTIONS'**
  String get reviewExportMarkdownOptions;

  /// Section label for EPUB-only export settings
  ///
  /// In en, this message translates to:
  /// **'EPUB OPTIONS'**
  String get reviewExportEpubOptions;

  /// PDF setting: embed recognized text
  ///
  /// In en, this message translates to:
  /// **'OCR (Make text searchable)'**
  String get reviewExportOcr;

  /// PDF image quality picker label
  ///
  /// In en, this message translates to:
  /// **'Image quality'**
  String get reviewExportImageQuality;

  /// Highest PDF image quality
  ///
  /// In en, this message translates to:
  /// **'High (Best)'**
  String get reviewExportQualityHigh;

  /// Balanced PDF image quality
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get reviewExportQualityMedium;

  /// Smaller PDF image quality
  ///
  /// In en, this message translates to:
  /// **'Low (Smaller)'**
  String get reviewExportQualityLow;

  /// Confirm button after choosing PDF
  ///
  /// In en, this message translates to:
  /// **'Export to PDF'**
  String get reviewExportToPdf;

  /// Confirm button after choosing Markdown
  ///
  /// In en, this message translates to:
  /// **'Export to Markdown'**
  String get reviewExportToMarkdown;

  /// Confirm button after choosing EPUB
  ///
  /// In en, this message translates to:
  /// **'Export to EPUB'**
  String get reviewExportToEpub;

  /// Export / Convert sheet: Word (.docx) format card title
  ///
  /// In en, this message translates to:
  /// **'Export as Word'**
  String get reviewExportWord;

  /// Export / Convert sheet: Word format card subtitle
  ///
  /// In en, this message translates to:
  /// **'An editable .docx with the scanned pages, for Microsoft Word or Google Docs.'**
  String get reviewExportWordHint;

  /// Export / Convert sheet confirm button for Word
  ///
  /// In en, this message translates to:
  /// **'Export to Word'**
  String get reviewExportToWord;

  /// Markdown setting: comment between pages
  ///
  /// In en, this message translates to:
  /// **'Page markers'**
  String get reviewIncludePageMarkers;

  /// Markdown setting: server writes maths as LaTeX
  ///
  /// In en, this message translates to:
  /// **'Recognize formulas (LaTeX)'**
  String get reviewRecognizeFormulas;

  /// Section label for Word-only export settings
  ///
  /// In en, this message translates to:
  /// **'WORD OPTIONS'**
  String get reviewExportWordOptions;

  /// Word setting: keep each page's layout instead of one reading flow
  ///
  /// In en, this message translates to:
  /// **'Keep page layout'**
  String get reviewKeepPageLayout;

  /// EPUB setting: embed the scanned page image
  ///
  /// In en, this message translates to:
  /// **'Include page images'**
  String get reviewIncludePageImages;

  /// Switches to list view so pages can be dragged
  ///
  /// In en, this message translates to:
  /// **'Page order'**
  String get reviewPageOrder;

  /// Default title of a page row when it has no custom label
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String reviewPageLabel(int number);

  /// Tooltip for the Review Add button
  ///
  /// In en, this message translates to:
  /// **'Add pages'**
  String get reviewAddPagesTooltip;

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

  /// Confirmation before deleting pages from Review
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete this page?} other{Delete {count} pages?}}'**
  String deletePagesConfirmTitle(int count);

  /// Warning under the delete-pages confirmation title
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get deletePagesConfirmBody;

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

  /// Dismiss a page anomaly warning badge
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismissWarning;

  /// Section header for PDF page size/orientation/margins/watermark
  ///
  /// In en, this message translates to:
  /// **'PDF options'**
  String get pdfOptionsSection;

  /// PDF page size picker label
  ///
  /// In en, this message translates to:
  /// **'Page size'**
  String get pdfPageSize;

  /// PDF orientation picker label
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get pdfOrientation;

  /// PDF margins picker label
  ///
  /// In en, this message translates to:
  /// **'Margins'**
  String get pdfMargins;

  /// Zero PDF margins
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pdfMarginsNone;

  /// Narrow PDF margins
  ///
  /// In en, this message translates to:
  /// **'Narrow'**
  String get pdfMarginsNarrow;

  /// Normal PDF margins
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get pdfMarginsNormal;

  /// Optional owner watermark text for PDF export
  ///
  /// In en, this message translates to:
  /// **'Watermark'**
  String get pdfWatermark;

  /// Hint for watermark text field
  ///
  /// In en, this message translates to:
  /// **'Optional text overlay'**
  String get pdfWatermarkHint;

  /// A4 page size
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get pdfPageSizeA4;

  /// US Letter page size
  ///
  /// In en, this message translates to:
  /// **'Letter'**
  String get pdfPageSizeLetter;

  /// US Legal page size
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get pdfPageSizeLegal;

  /// PDF page size matches source image aspect
  ///
  /// In en, this message translates to:
  /// **'Match page'**
  String get pdfPageSizeMatchSource;

  /// Portrait orientation
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get pdfOrientationPortrait;

  /// Landscape orientation
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get pdfOrientationLandscape;

  /// Auto orientation from page
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get pdfOrientationAuto;

  /// Print completed export via system print sheet
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printAction;

  /// Save completed export via system file picker
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get saveAsAction;

  /// OCR language option: English
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get ocrLanguageEnglish;

  /// OCR language option: Spanish
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get ocrLanguageSpanish;

  /// OCR language option: French
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get ocrLanguageFrench;

  /// OCR language option: German
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get ocrLanguageGerman;

  /// OCR language option: Portuguese
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get ocrLanguagePortuguese;

  /// OCR language option: Italian
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get ocrLanguageItalian;

  /// Menu action to open manual crop correction
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropAction;

  /// Menu action to set cover/Roman/custom page label
  ///
  /// In en, this message translates to:
  /// **'Page number / label'**
  String get pageLabelAction;

  /// Dialog title for editing logical page label
  ///
  /// In en, this message translates to:
  /// **'Page label'**
  String get pageLabelTitle;

  /// Hint for logical page label field
  ///
  /// In en, this message translates to:
  /// **'e.g. Cover, iii, 12'**
  String get pageLabelHint;

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

  /// PageFilter.enhancedColor — industry-standard document scan look
  ///
  /// In en, this message translates to:
  /// **'Document'**
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

  /// Arbitrary-angle rotation slider label
  ///
  /// In en, this message translates to:
  /// **'Fine rotation'**
  String get fineRotationLabel;

  /// Black & white binarization threshold slider label
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get thresholdLabel;

  /// Menu action resetting a page's filter/adjustments/crop/rotation back to defaults
  ///
  /// In en, this message translates to:
  /// **'Revert to original'**
  String get revertToOriginal;

  /// Menu action to open manual book-spread split correction, only shown for pages from a split spread
  ///
  /// In en, this message translates to:
  /// **'Re-split spread'**
  String get spreadSplitAction;

  /// Menu action on a book page that holds a whole two-page spread; splits it at the centre into two pages
  ///
  /// In en, this message translates to:
  /// **'Split into two pages'**
  String get splitIntoTwoPagesAction;

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

  /// Tap Scanner–style reset of the crop frame to the full image
  ///
  /// In en, this message translates to:
  /// **'No Crop'**
  String get cropNoCrop;

  /// Rotate crop preview 90° counter-clockwise
  ///
  /// In en, this message translates to:
  /// **'Rotate L'**
  String get cropRotateLeft;

  /// Rotate crop preview 90° clockwise
  ///
  /// In en, this message translates to:
  /// **'Rotate R'**
  String get cropRotateRight;

  /// Apply crop and continue to filters (or back to review)
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get cropNext;

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

  /// Export format option: each page as a standalone image file
  ///
  /// In en, this message translates to:
  /// **'Images (JPG/PNG)'**
  String get exportImages;

  /// Image export format choice
  ///
  /// In en, this message translates to:
  /// **'JPG'**
  String get exportImagesFormatJpg;

  /// Image export format choice
  ///
  /// In en, this message translates to:
  /// **'PNG'**
  String get exportImagesFormatPng;

  /// Opens the PDF compress-quality dialog
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compressAction;

  /// PDF compress quality slider label
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get compressQualityLabel;

  /// Live estimated output size shown in the compress dialog
  ///
  /// In en, this message translates to:
  /// **'Estimated size: {size}'**
  String compressEstimatedSize(String size);

  /// Generic apply/confirm action
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

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

  /// Shown over the page preview while a filter or adjustment is being rendered
  ///
  /// In en, this message translates to:
  /// **'Applying…'**
  String get applyingChanges;

  /// Shown over the page preview while an edit is being saved
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingChanges;

  /// Shown when saving a crop, filter or split edit fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your changes. Please try again.'**
  String get saveChangesFailed;

  /// Shown when a gallery or PDF import added no pages (failed, or the file had none)
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import any pages from that file.'**
  String get importFailed;

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

  /// Section header for capture-related settings
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get settingsCaptureSection;

  /// Setting for the pre-capture countdown timer
  ///
  /// In en, this message translates to:
  /// **'Capture countdown'**
  String get settingsCountdown;

  /// Countdown option: no delay before capture
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsCountdownOff;

  /// Toggle to keep auto-capturing without waiting for the scene to change
  ///
  /// In en, this message translates to:
  /// **'Continuous capture'**
  String get settingsContinuousCapture;

  /// Toggle for a vibration when a page is captured
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback on capture'**
  String get settingsHapticConfirmation;

  /// Toggle for a shutter sound when a page is captured
  ///
  /// In en, this message translates to:
  /// **'Sound on capture'**
  String get settingsAudioConfirmation;

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

  /// Button to dismiss the first-launch onboarding carousel
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// Advances to the next onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// Button on the final onboarding slide that finishes onboarding
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// Headline of the first onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Scan Documents in Seconds'**
  String get onboardingScanTitle;

  /// Body text of the first onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Edges are found for you. Get a crisp, ready-to-share PDF straight from your camera.'**
  String get onboardingScanBody;

  /// Headline of the second onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Scan Books Fast'**
  String get onboardingBookTitle;

  /// Body text of the second onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Scan page after page in one go. Photographed a two-page spread? Split it in one tap.'**
  String get onboardingBookBody;

  /// Headline of the third onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Export & Stay Organized'**
  String get onboardingOrganizeTitle;

  /// Body text of the third onboarding slide
  ///
  /// In en, this message translates to:
  /// **'Save as PDF, Word, EPUB or Markdown with searchable text, and find any scan in seconds.'**
  String get onboardingOrganizeBody;

  /// Small label over the first onboarding picture
  ///
  /// In en, this message translates to:
  /// **'Edges detected'**
  String get onboardingScanChip;

  /// Small label over the second onboarding picture
  ///
  /// In en, this message translates to:
  /// **'Page after page'**
  String get onboardingBookChip;

  /// Example search word shown in the third onboarding illustration
  ///
  /// In en, this message translates to:
  /// **'photosynthesis'**
  String get onboardingSearchSample;

  /// Caption under PDF in the third onboarding illustration
  ///
  /// In en, this message translates to:
  /// **'Searchable'**
  String get onboardingFormatSearchable;

  /// Caption under DOCX in the third onboarding illustration
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get onboardingFormatWord;

  /// Caption under EPUB in the third onboarding illustration
  ///
  /// In en, this message translates to:
  /// **'eBook'**
  String get onboardingFormatEbook;

  /// Caption under MD in the third onboarding illustration
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get onboardingFormatMarkdown;

  /// Headline of the app-lock unlock screen
  ///
  /// In en, this message translates to:
  /// **'BookScanner is locked'**
  String get unlockTitle;

  /// Subtitle of the app-lock unlock screen
  ///
  /// In en, this message translates to:
  /// **'Confirm it\'s you to continue'**
  String get unlockSubtitle;

  /// Button that starts biometric/PIN authentication
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// Shown after a failed or cancelled unlock attempt
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify — try again'**
  String get unlockFailed;

  /// Shown when the Favorites page has no starred projects
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get favoritesEmptyTitle;

  /// Subtitle under the empty Favorites state
  ///
  /// In en, this message translates to:
  /// **'Tap the star on a scan to add it here'**
  String get favoritesEmptySubtitle;

  /// Shown when the Trash page has no deleted projects
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashEmptyTitle;

  /// Subtitle under the empty Trash state
  ///
  /// In en, this message translates to:
  /// **'Deleted scans appear here so you can restore or remove them forever'**
  String get trashEmptySubtitle;

  /// Restores a project out of the trash
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreAction;

  /// Permanently and irreversibly deletes a trashed project
  ///
  /// In en, this message translates to:
  /// **'Delete Forever'**
  String get deleteForeverAction;

  /// Title of the confirmation dialog before permanently deleting a project
  ///
  /// In en, this message translates to:
  /// **'Delete forever?'**
  String get deleteForeverConfirmTitle;

  /// Body of the confirmation dialog before permanently deleting a project
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone. \"{title}\" and its pages will be permanently deleted.'**
  String deleteForeverConfirmBody(String title);

  /// Body of the confirmation dialog before permanently deleting multiple trashed projects
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This can\'t be undone. 1 selected scan and its pages will be permanently deleted.} other{This can\'t be undone. {count} selected scans and their pages will be permanently deleted.}}'**
  String deleteForeverConfirmBodySelected(int count);
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
