# BookScanner Product Specification

**Document status:** Draft v1.0  
**Platforms:** iOS and Android  
**Product type:** Mobile document and book scanning application  
**Working name:** BookScanner

## 1. Product vision

BookScanner turns a phone into a high-quality portable scanner for documents and bound books. A user can scan one page or hundreds of pages, correct and enhance the images, create a searchable PDF, or convert the scanned content into editable Markdown (`.md`) or Microsoft Word (`.docx`).

The product must be useful offline for scanning and basic processing. Cloud processing may be offered for higher-accuracy OCR and document reconstruction, but only with clear consent.

## 2. Goals

1. Let users scan documents with quality comparable to leading mobile scanner apps.
2. Make long book-scanning sessions fast, reliable, and recoverable.
3. Produce clean PDFs that preserve the visual appearance of the original pages.
4. Produce editable Markdown and Word documents that preserve reading order, headings, paragraphs, lists, tables, images, footnotes, and page boundaries where possible.
5. Protect private documents and respect copyright and data-protection requirements.

## 3. Non-goals for the first release

- Perfect reconstruction of every complex book layout, handwritten page, equation, or decorative typeface.
- Removing DRM or bypassing copyright controls.
- Guaranteeing that a scan is legally equivalent to a certified copy.
- Collaborative real-time editing.
- Desktop publishing or full Word-style document editing inside the app.

## 4. Target users

- Students digitizing personally owned or permitted study material.
- Researchers archiving notes, public-domain works, and source material.
- Teachers converting handouts into accessible digital documents.
- Professionals scanning contracts, receipts, forms, IDs, and reports.
- Archivists and small organizations digitizing material they have permission to reproduce.

## 5. Core user journeys

### 5.1 Scan a document to PDF

1. The user taps **New Scan** and selects **Document**.
2. The camera detects the page boundary and captures automatically when stable, or the user presses the shutter.
3. The app corrects perspective, crops, rotates, removes shadows, and applies the chosen filter.
4. The user scans more pages, then reviews, reorders, rotates, crops, deletes, or rescans pages.
5. The user names the document and exports a normal or searchable PDF.

### 5.2 Scan a bound book

1. The user taps **New Scan** and selects **Book**.
2. The user enters optional metadata: title, author, language, starting page number, and scan mode (single page or two-page spread).
3. The camera provides alignment, glare, focus, hand/finger, and lighting guidance.
4. Auto-capture records each stable page or spread. Two-page spreads are split into separate pages.
5. The app flattens curved pages, corrects perspective, removes background/shadows, and assigns page numbers.
6. Progress is saved after every capture so the session can be resumed safely.
7. Before export, the app flags blurred, duplicated, missing, out-of-order, or low-confidence pages.
8. The user exports a faithful searchable PDF or runs **Convert to editable document** for Markdown or Word.

### 5.3 Convert a book to Markdown or Word

1. The user chooses an existing book scan and an output format: Markdown or Word.
2. OCR detects text and layout, then reconstructs headings, paragraphs, lists, tables, captions, images, headers/footers, footnotes, and page breaks.
3. The app shows uncertain text and layout warnings in a review screen.
4. The user compares the page image with extracted content and edits errors.
5. The app exports `.md` plus an assets folder, or a self-contained `.docx` file.

## 6. Functional requirements

### 6.1 Camera and capture

- Live automatic document-edge detection.
- Automatic capture when the page is in focus, stable, sufficiently lit, and fully visible.
- Manual shutter, flash/torch, zoom, focus, and exposure controls.
- Import one or many images from the photo library.
- Import an existing PDF for editing, OCR, splitting, or conversion.
- Single-page, batch, book-spread, ID-card, receipt, and QR/barcode capture modes.
- Real-time warnings for blur, glare, low light, clipped edges, severe skew, and fingers covering content.
- Configurable countdown and automatic continuous capture.
- Haptic and audio capture confirmation, both independently disableable.

### 6.2 Image processing

- Automatic crop, perspective correction, rotation, and orientation detection.
- Book-page dewarping and gutter-curve correction.
- Split a two-page book spread into correctly ordered individual pages.
- Filters: original/color, enhanced color, grayscale, black-and-white, and photo.
- Adjustable brightness, contrast, sharpness, and threshold.
- Shadow, stain, noise, and background cleanup without erasing printed content.
- Manual four-corner crop and fine rotation.
- Page-level undo and access to the original image until the user deletes it.
- Quality score for every page and suggested rescans for unreadable pages.

### 6.3 Multi-page and book session management

- Handle at least 500 pages in one project without loading every full-resolution image into memory.
- Save each page and project metadata immediately after capture.
- Resume an interrupted session after app termination, restart, or device reboot.
- Thumbnail grid with select, reorder, rotate, duplicate, delete, and rescan actions.
- Automatic sequential page numbering with support for covers, Roman numerals, skipped numbers, and unnumbered pages.
- Detect likely duplicate pages using image similarity and OCR text similarity.
- Detect likely missing pages from printed page numbers and scan sequence; warnings must be reviewable and dismissible.
- Support right-to-left books and configurable page order.
- Store book metadata: title, author, language, edition, ISBN, tags, and notes.

### 6.4 OCR and document understanding

- OCR printed text with an initial language set defined before implementation; English is required for MVP.
- Allow the user to select one or more document languages.
- Preserve reading order in single- and multi-column layouts.
- Detect headings, paragraphs, lists, tables, captions, quotations, page numbers, headers/footers, footnotes/endnotes, and embedded images.
- Mark low-confidence words and uncertain layout regions for review.
- Let users search, select, copy, and edit recognized text.
- Create a searchable PDF by placing an invisible text layer over page images.
- Never silently replace uncertain content; retain the page image as the source of truth.
- Mathematical notation, handwriting, and complex tables may use best-effort recognition and must be labeled when confidence is low.

### 6.5 PDF creation and editing

- Export multi-page PDF with selectable page size, orientation, margins, image quality, and compression.
- Export searchable or image-only PDF.
- Merge PDFs and scanned projects.
- Split a PDF by page selection or ranges.
- Insert, replace, extract, duplicate, rotate, reorder, and delete pages.
- Convert images to PDF and PDF pages to JPG/PNG.
- Add annotations, highlights, text, dates, shapes, redaction, and a drawn/imported signature.
- Compress PDFs with estimated output size and a quality preview.
- Add/remove an owner-created watermark.
- Protect exported PDFs with a password and supported encryption.
- Share, save to the system file picker, and print through platform services.

### 6.6 Markdown export

- Export UTF-8 Markdown with headings, paragraphs, lists, block quotes, links, and fenced code blocks where detected.
- Represent simple tables as Markdown tables; use embedded HTML or an image fallback for layouts Markdown cannot express faithfully.
- Save page images and extracted figures in an adjacent `assets/` directory and reference them with relative paths.
- Add optional page-boundary comments such as `<!-- Page 42 -->`.
- Offer YAML front matter containing title, author, language, ISBN, scan date, and source metadata.
- Package the Markdown file and assets as a ZIP when sharing through destinations that require a single file.

### 6.7 Word export

- Export a standards-compliant `.docx` document.
- Map detected structure to Word heading styles, body text, lists, tables, captions, footnotes, headers/footers, images, and page breaks.
- Preserve page boundaries optionally; allow a reflowable mode optimized for editing.
- Include source page images only when the user selects a facsimile or side-by-side export option.
- Embed document metadata and the OCR language.

### 6.8 Organization and discovery

- Local library with recent items, folders, tags, favorites, and trash/recovery.
- Rename one item or batch-rename with a pattern.
- Search by filename, metadata, tags, and OCR text.
- Sort and filter by date, title, type, page count, and size.
- Thumbnail and list views.
- Optional secure cloud backup and sync. Provider integrations are post-MVP unless selected during implementation.
- Detect file conflicts and never overwrite a newer version silently.

### 6.9 Security and privacy

- Core scanning and local storage work without an account.
- Encrypt sensitive app data at rest using platform-provided secure storage and file-protection APIs.
- Optional app lock using device PIN/biometrics.
- Clearly identify which OCR/export features run on-device and which upload content.
- Obtain explicit consent before the first cloud upload and provide deletion controls.
- Do not use document content to train models unless the user separately opts in.
- Strip location metadata from exported scans by default.
- Provide account export and deletion if accounts/cloud storage are introduced.

### 6.10 Copyright and responsible use

- During book onboarding, tell users to scan only content they own, that is public domain, or that they are authorized to reproduce.
- Do not market the app as a way to pirate or redistribute books.
- Sharing/export remains available for lawful use; the app records no claim that the user owns copyright.
- Provide a configurable acknowledgement before very large book exports.

### 6.11 Accessibility and localization

- Support screen readers, dynamic text, sufficient contrast, large touch targets, and reduced-motion settings.
- Every camera control has an accessible label and non-visual feedback.
- Do not rely on color alone for quality warnings.
- Prepare all UI strings for localization.
- Support left-to-right and right-to-left interfaces and document reading order.

## 7. Tap Scanner benchmark parity

“All features” is interpreted as parity with the publicly advertised capabilities at the time this specification was written, not a pixel-for-pixel clone. The parity backlog includes:

- Camera/gallery scanning, auto-crop/alignment, enhancement, and batch capture.
- OCR, editable extracted text, and searchable documents.
- QR/barcode scanning.
- PDF merge, split, reorder, compression, and PDF/image conversion.
- PDF-to-Word and Word-to-PDF conversion.
- Annotations, text/date insertion, signatures, cleanup, watermark handling, and password protection.
- Folders, tags, file search, automatic organization, and cloud backup.
- Sharing, email, messaging integration through the platform share sheet, and printing.

Branding, proprietary UI, copyrighted assets, and implementation details from any competitor must not be copied.

## 8. MVP scope

The first production release should prioritize scan quality and reliability:

1. iOS and Android camera capture with auto-detection and manual capture.
2. Batch document and book scanning, including spread splitting and basic dewarping.
3. Crop, rotate, filters, enhancement, page reorder/delete/rescan, and crash-safe resume.
4. Image-only and searchable PDF export.
5. English printed-text OCR, search, copy, and low-confidence review.
6. Editable Markdown and Word export for common single-column layouts.
7. Local folders, tags, filename/OCR search, share, and print.
8. Offline-first storage, biometric app lock, and explicit cloud-processing consent if cloud OCR is used.

Deferred parity items include signatures, advanced PDF editing, QR scanning, cloud sync providers, PDF/Word round-trip conversion, handwriting/equation OCR, and multi-user collaboration.

## 9. Suggested technical architecture

### 9.1 Mobile client

- Use Flutter for the shared application shell: navigation, library, project management, page review/reordering, OCR correction, settings, subscriptions, and export flows.
- Structure Flutter code using the layered MVVM/repository approach defined by the local `flutter-apply-architecture-best-practices` skill: lean Views, immutable ViewModel state, Repositories as the domain-facing source of truth, Services around databases/network/platform plugins, and Use Cases only for complex or reusable domain logic.
- Organize shared code into `data/`, `domain/`, and `ui/`, with UI grouped by feature. Native scanner adapters are Services/infrastructure and must not leak into Views or ViewModels.
- Follow the local `dart-flutter-patterns` skill for null safety, immutable/sealed state, async composition, widget extraction, scoped rebuilds, error handling, networking, storage, and unit/widget test patterns. Avoid unchecked `!`, unnecessary `late`, mutable shared state, and business logic in widgets.
- Implement capture as a first-party Flutter plugin with a common Dart API and native implementations:
  - **Android:** Kotlin, CameraX `Preview`, `ImageCapture`, and `ImageAnalysis`.
  - **iOS:** Swift, AVFoundation capture session/photo output, plus Vision/VisionKit where appropriate.
- Use Flutter platform channels for commands, state, warnings, progress, and file paths. Do not send live camera frames or full-resolution page byte arrays through a method channel.
- Render the native preview efficiently with the supported Flutter texture/platform-view mechanism. Run frame analysis and image processing off the UI thread.
- Keep the scanner contract platform-neutral so Android and iOS return the same page, crop, quality, warning, and processing-state models.
- Flutter code must depend on stable BookScanner domain interfaces, not directly on CameraX, AVFoundation, Vision, ML Kit, OpenCV, Core ML, TensorFlow Lite/LiteRT, or any third-party Flutter plugin. Native frameworks and libraries must be hidden behind replaceable adapters.
- Replacing a native capture, OCR, dewarping, enhancement, or export provider must not require changes to Flutter screens, navigation, project storage, review workflows, or business rules. Flutter-side changes should be limited to an intentionally versioned contract only when the product capability itself changes.
- Local relational database stores projects, pages, OCR blocks, metadata, and job state.
- Full-resolution page images are stored as files; thumbnails are generated separately.
- Background job queue handles enhancement, OCR, PDF generation, and exports with pause/resume and progress reporting.
- Processing pipeline is page-based and idempotent so one failed page can be retried without restarting a book.

### 9.1.1 Flutter application structure

```text
lib/
├── data/
│   ├── models/                 # Serialized database/API/platform DTOs
│   ├── repositories/           # Repository implementations
│   └── services/
│       ├── local/              # Database and file storage
│       ├── remote/             # Optional backend/cloud clients
│       └── scanner/            # Vendor-neutral platform service + adapters
├── domain/
│   ├── models/                 # Immutable BookScanner models
│   ├── repositories/           # Abstract repository contracts
│   └── use_cases/              # Capture, process, OCR, resume, and export rules
├── routing/                    # Router, route parsing, guards, and error routes
├── l10n/                       # ARB localization resources
└── ui/
    ├── core/                   # Theme, accessibility, shared widgets
    └── features/
        ├── library/
        ├── capture/
        ├── page_review/
        ├── ocr_review/
        ├── export/
        └── settings/
```

Each new feature follows this order: define immutable domain models; implement Services; implement Repositories; add Use Cases only if needed; implement the ViewModel; implement lean Views; register dependencies; then run unit, widget, analyzer, and applicable integration checks.

### 9.2 Native capture and analysis design

- The live-analysis stream uses reduced-resolution frames for edge, stability, blur, glare, and finger detection. Final processing uses the separately captured full-resolution still image.
- Android CameraX analysis uses a keep-only-latest backpressure policy so slow analysis drops stale frames instead of freezing the preview. Every `ImageProxy` must be closed promptly.
- iOS uses a serial analysis queue and discards late video frames. Still capture remains independent of analysis so the preview and shutter stay responsive.
- Auto-capture requires all configured gates to remain satisfied for a short stable window: page detected, corners stable, device motion below threshold, focus acceptable, exposure acceptable, and no blocking warning.
- Persist the original still image immediately. Enhancement, dewarping, OCR, and export run as cancellable background jobs from the stored file.
- Return normalized corner coordinates and overlay geometry to Flutter; apply the platform camera-preview transform before drawing guidance.
- Provide manual capture and manual four-corner correction on every supported device, including devices that cannot run optional ML models.

### 9.3 Computer-vision strategy

- Use a fast classical pipeline for flat documents: luminance conversion, contour/line candidates, quadrilateral scoring, perspective transform, orientation, adaptive enhancement, and blur/exposure metrics.
- Use a learned segmentation/dewarping pipeline for bound books. It should estimate left/right page masks, gutter/center line, page surface deformation, and occlusions such as fingers; then generate backward-remap fields for flattening.
- Treat two-page splitting, curve flattening, and finger removal as independent, versioned stages. A user can disable or manually correct each stage.
- Maintain one shared C++ image-processing core where practical, using OpenCV-style primitives, with thin Kotlin/Swift bindings. Package learned models for each platform runtime rather than running inference in Dart.
- Evaluate Core ML on iOS and TensorFlow Lite/LiteRT on Android for low-latency on-device models. A portable model format may be retained as the training/export source, but device-specific quantization and acceleration must be benchmarked.
- Never invent pixels over text silently during finger/occlusion removal. If reconstruction confidence is low, preserve the original region, warn the user, and recommend a rescan.

### 9.4 OCR and layout strategy

- OCR runs after geometric correction because perspective and page curvature reduce recognition accuracy.
- For the first on-device implementation, use Apple Vision text recognition on iOS and ML Kit Text Recognition v2 on Android. Normalize their outputs into the common OCR block model.
- Use fast recognition only for live guidance. Use the accurate/full-resolution path for saved pages.
- Preserve bounding polygons, confidence, language, line/block hierarchy, and source-page coordinates; plain text alone is insufficient for searchable PDF or structured DOCX/Markdown.
- Add a separate layout-analysis stage for reading order, headings, columns, tables, captions, figures, headers/footers, and footnotes. Platform OCR output must not be assumed to reconstruct a book automatically.
- Higher-accuracy cloud OCR/layout processing may be offered later, but the user must explicitly opt in and the app must keep an offline path.

### 9.5 Processing pipeline

`Capture/import -> quality check -> edge detection -> crop/perspective correction -> dewarp/split -> enhancement -> OCR/layout analysis -> user review -> export`

Each pipeline stage stores its version and output. Changing a crop or filter invalidates only dependent stages.

### 9.6 Build-versus-buy decisions

- **Do not use Google ML Kit Document Scanner as the primary Android capture UI.** It is useful for a fallback or prototype and produces JPEG/PDF with a small app-size impact, but its Google-provided UI and dynamically downloaded scanning logic do not give BookScanner enough control over long book sessions, custom overlays, dewarping, page-turn detection, or matching behavior on iOS.
- **Do not use `VNDocumentCameraViewController` as the primary iOS capture UI.** It is a strong fallback for basic page-by-page document scanning, but its system-owned flow is not sufficiently customizable for BookScanner's book guidance and cross-platform UX.
- Use the platform-provided scanners as optional basic-document fallbacks while our native CameraX/AVFoundation capture experience remains the main path.
- Use platform OCR for MVP, but own the common OCR schema, correction history, PDF text-layer generation, and layout reconstruction so providers can be replaced later.

### 9.7 Replaceable native-provider architecture

- Define capability-based Dart interfaces such as `CaptureProvider`, `PageDetectionProvider`, `ImageEnhancementProvider`, `BookDewarpProvider`, `OcrProvider`, and `DocumentExportProvider`. Application features consume these interfaces through dependency injection rather than importing provider implementations.
- Treat the platform-channel/plugin wrapper as a Service under the architecture skill. Repositories and Use Cases consume its canonical domain results; ViewModels and Views never call method channels directly.
- Maintain one versioned platform contract for commands, events, errors, capabilities, and normalized result models. Generate or centrally define the Dart, Kotlin, and Swift contract types where practical to prevent platform drift.
- Each native library is integrated through a small adapter that converts library-specific inputs, outputs, coordinates, confidence values, and errors into BookScanner's canonical models.
- Provider selection belongs in a composition/configuration layer. It may select providers by platform, OS version, device capability, feature flag, privacy setting, or benchmark result without changing calling features.
- Support capability discovery instead of assuming every provider offers every feature. For example, the Flutter layer asks whether live edge detection, offline OCR, handwriting, dewarping, or a language is supported and adapts the UI gracefully.
- Use stable error categories such as permission denied, unsupported device, model unavailable, processing failed, cancelled, and recoverable low quality. Provider-specific error codes may be retained only as diagnostic metadata.
- Pass immutable job requests and file-based outputs across the boundary. Avoid exposing native object handles or vendor-specific types to Flutter.
- Persist provider name, adapter version, model version, and processing options with each derived artifact so results can be reproduced, invalidated, or regenerated after a provider change.
- Contract tests must run against every adapter. Golden-image and OCR corpus tests compare provider behavior without coupling product tests to a particular vendor.
- Keep fallback adapters available where useful. A provider failure or unavailable model may fall back to manual capture, basic perspective correction, or another OCR engine without losing the user's confirmed source image.
- Upgrading or replacing a provider must include a migration note, benchmark comparison, privacy/license review, and adapter-level tests; it must not require a broad Flutter rewrite.

### 9.8 Optional backend

- Authentication and encrypted cloud backup/sync.
- Higher-accuracy OCR and layout reconstruction.
- Conversion workers for complex DOCX output.
- Short-lived signed upload/download URLs, per-user authorization, malware scanning for imports, rate limits, audit events, and automatic deletion of temporary processing files.

The client must remain able to scan and generate an image-only PDF when the backend is unavailable.

## 10. Core data model

- **Project:** id, type, title, metadata, language, page order, created/updated timestamps, processing state.
- **Page:** id, project id, sequence, logical page label, original image, processed image, thumbnail, crop points, rotation, filter, quality score, status.
- **OCR block:** page id, bounding polygon, text, confidence, language, block type, reading order, user corrections.
- **Export job:** project id, format, options, progress, error, output location, created/completed timestamps.
- **Folder/tag:** local organization and optional sync identifiers.

## 11. Non-functional requirements

- Camera preview and capture controls remain responsive during background processing.
- A captured page appears in the thumbnail strip within 1 second on a supported mid-range device under normal lighting.
- No captured page is lost after the app confirms capture.
- A 300-page project can be opened, reordered, resumed, and exported without an out-of-memory crash.
- PDF page order exactly matches the reviewed project order.
- Exported OCR text uses Unicode and remains selectable/searchable in common PDF viewers.
- Long operations expose progress, can be cancelled safely, and provide actionable retry errors.
- Temporary files are cleaned after success/cancellation without deleting source scans.
- Automated crash reporting must exclude page images and OCR text.

## 12. Acceptance criteria

### Document scan

- Given a rectangular document photographed at an angle, the saved page is cropped and perspective-corrected, and the user can manually adjust all four corners.
- Given 20 captured pages, the user can reorder them and export one PDF whose page order matches the grid.

### Book scan

- Given a clear two-page spread, the app creates two ordered pages and lets the user correct the split.
- Given an interrupted 100-page scan, reopening the app restores all confirmed pages and resumes at the next page.
- Given consecutive pages with one likely duplicate or gap, the review screen flags the issue without blocking export.

### OCR and export

- Given a clear English printed page, recognized text is selectable, searchable, editable, and associated with the source page.
- Given corrected OCR text, a new export includes the correction and does not modify the original page image.
- Markdown export opens with valid UTF-8 text and working relative image links.
- Word export opens in current Microsoft Word and preserves common headings, paragraphs, lists, images, and page order.

### Provider replaceability

- Given a test replacement OCR adapter returning the canonical OCR model, the existing Flutter review, search, correction, searchable-PDF, Markdown, and Word workflows pass without screen or business-logic changes.
- Given a test replacement capture adapter implementing the versioned contract, the existing Flutter capture controls, page review, project persistence, and recovery workflows operate without provider-specific imports.
- Disabling an optional native capability causes the Flutter UI to hide or explain that capability based on provider discovery rather than crash or invoke vendor-specific logic.
- No Flutter feature module imports a native vendor SDK wrapper directly; only the infrastructure/composition layer may select a concrete adapter.

### Privacy

- The user can scan and generate an image-only PDF in airplane mode without creating an account.
- No page is uploaded before the user has seen and accepted a clear cloud-processing disclosure.

## 13. Quality and test plan

- Test on representative low-, mid-, and high-end iOS and Android devices.
- Build a consented test corpus covering flat pages, curved books, glossy paper, shadows, fingers, skew, low light, multi-column layouts, tables, illustrations, and right-to-left text.
- Measure edge accuracy, blur/glare detection, split/dewarp success, OCR character/word error rate, reading-order accuracy, export validity, processing time, memory use, battery use, and crash-free sessions.
- Include unit, pipeline golden-image, database migration, export validation, accessibility, offline, interrupted-job, low-storage, permission-denied, and security tests.
- Configure Flutter's `integration_test` package and give critical interactive controls stable `ValueKey`s, following the local `flutter-add-integration-test` skill. Convert important manually explored flows into permanent tests.
- Integration tests must cover: first launch/permissions, document capture with a fake adapter, multi-page book session, interrupted-session recovery, page reorder/rescan, OCR correction, PDF/Markdown/DOCX export, provider fallback, localization switching, and essential navigation/back behavior.
- Run integration tests on at least one physical or virtual Android target and one iOS simulator/device in CI or release validation. Use performance tracing for page-grid scrolling and long-session review when regressions are suspected.
- Apply the local `flutter-fix-layout-issues` workflow to constraint exceptions and visual overflow. Capture the primary error, fix the violated constraint rather than cascading errors, hot reload, and repeat validation. Test compact phones, tablets, landscape, text scaling, long translations, keyboard-visible layouts, and right-to-left direction.
- Manually inspect generated PDFs, Markdown packages, and DOCX files before each release.

## 14. Product decisions required before implementation

1. Initial OCR languages beyond English.
2. On-device-only OCR versus a hybrid cloud option.
3. Free, paid, subscription, or usage-based business model.
4. Whether cloud backup launches with MVP and which providers are first.
5. Maximum supported pages/project and local storage policy.
6. Whether Word conversion must support complex tables, equations, and footnotes at launch.
7. Minimum supported iOS/Android versions and target device performance tier.

## 15. Delivery phases

- **Phase 0 — Foundation and prototype:** initialize Flutter architecture and localization using the copied skills; establish routing, provider contracts, fake adapters, test harness, camera quality, edge detection, book spread splitting, dewarping, and OCR accuracy tests.
- **Phase 1 — MVP:** build each feature through the architecture workflow; deliver reliable scanning, local projects, searchable PDF, basic Markdown/DOCX export, review workflow, and critical Android/iOS integration tests.
- **Phase 2 — Scanner parity:** annotations, signatures, advanced PDF tools, QR scanning, protection, conversion, and cloud integrations.
- **Phase 3 — Advanced books:** more languages, complex layout recovery, handwriting/equations, stronger duplicate/gap detection, and large-library sync.

## 16. Benchmark sources

The parity interpretation was based on Tap Scanner's public product listings and website reviewed on 2026-07-19:

- Tap Scanner website: https://tap-scanner.com/
- Apple App Store listing: https://apps.apple.com/la/app/tapscanner-scanner-app-to-pdf/id1382564905
- Google Play listing: https://play.google.com/store/apps/details?id=pdf.tap.scanner
- Tap Mobile product page: https://tap.pm/our-products/

## 17. Implementation research and lessons

Research reviewed on 2026-07-19 distinguishes publicly documented behavior from private implementation details. Adobe and vFlat do not publish their complete production architecture or models, so the specification does not claim to know their internal source code.

### 17.1 Popular-product patterns

- **Adobe Scan:** Adobe publicly describes automatic border detection, capture, lighting/perspective cleanup, multi-page optimization, OCR, searchable PDF, review/edit operations, and Document Cloud integration. The lesson is to separate capture and cleanup from OCR/PDF services and let users review before downstream document workflows.
- **Dropbox scanner/OCR:** Dropbox publicly described a production OCR pipeline that combined OpenCV MSER candidate detection with convolutional networks, bidirectional LSTMs, and CTC recognition, plus extensive performance tuning. The lesson is that OCR is a multi-stage production system—not a single “image to text” call—and that geometry, detection, recognition, and post-processing should be separately testable.
- **Microsoft Lens/OneDrive:** Microsoft exposes capture modes optimized for documents, whiteboards, business cards, and photos, followed by crop, rotate, filter, multi-page PDF, OCR, and Word-related workflows. The lesson is to use mode-specific capture/enhancement profiles rather than one filter for every source. Microsoft Lens itself was retired in 2026, also showing why our project data and processing contracts should not depend on one vendor product.
- **vFlat:** vFlat publicly advertises book-specific automatic page detection/cropping, two-page capture, curve flattening, finger removal, OCR, and PDF/JPG/TXT output. The lesson is that a credible book mode needs its own segmentation and learned rectification pipeline; ordinary four-corner perspective correction is not enough.

### 17.2 Platform findings

- Google's Android ML Kit Document Scanner supplies its own viewfinder/review flow and returns JPEG/PDF. Its models, scanning logic, and UI are downloaded through Google Play services. This is valuable for basic scanning, but it is Android-specific and too constrained to be BookScanner's primary book interface.
- Apple's `VNDocumentCameraViewController` returns page images from a system document-camera UI that applications can turn into PDFs. It is suitable for a simple fallback, while a custom AVFoundation/Vision pipeline is required for branded overlays, live book guidance, and identical Android/iOS session behavior.
- CameraX `ImageAnalysis` explicitly supports frame backpressure. Keeping only the newest frame is appropriate for live guidance because stale detections have no value and queued analysis can stall the preview.
- Apple Vision OCR supports fast and accurate recognition, language selection, language correction, confidence, and bounding boxes on-device. ML Kit Text Recognition v2 provides blocks, lines, elements, coordinates, and on-device recognition on Android/iOS. BookScanner should normalize provider output rather than expose provider-specific models to Flutter.
- Flutter officially supports calling Kotlin/Swift through platform channels. Channels are appropriate for control messages and results, while native code should retain ownership of high-rate frame buffers and full-resolution processing.

### 17.3 Research-backed proof-of-concept gates

Before full implementation, build and compare native Android and iOS prototypes using the same consented test corpus. Proceed only when:

1. Flat-page edge overlays remain responsive while analysis drops stale frames.
2. Auto-capture avoids duplicates during page turns and does not fire on blurred or partially visible pages.
3. At least 95% of clear two-page test spreads are split in the correct reading order; manual correction covers failures.
4. Dewarping improves OCR error rate on curved-page tests and does not materially distort illustrations or flat pages.
5. Finger detection never removes high-confidence text without warning; uncertain cases request a rescan.
6. A 300-page session survives repeated backgrounding, termination, low-memory conditions, and resume without losing a confirmed capture.

### 17.4 Technical sources

- Google ML Kit Document Scanner for Android: https://developers.google.com/ml-kit/vision/doc-scanner/android
- Android CameraX image analysis: https://developer.android.com/media/camera/camerax/analyze
- Apple VisionKit document camera: https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller
- Apple Vision text recognition: https://developer.apple.com/documentation/vision/recognizing-text-in-images
- Google ML Kit Text Recognition v2 for iOS: https://developers.google.com/ml-kit/vision/text-recognition/v2/ios
- Flutter platform channels: https://docs.flutter.dev/platform-integration/platform-channels
- Adobe Scan introduction: https://blog.adobe.com/en/publish/2017/05/31/new-adobe-scan-app-for-document-cloud
- Dropbox production OCR pipeline: https://dropbox.tech/machine-learning/creating-a-modern-ocr-pipeline-using-computer-vision-and-deep-learning
- Microsoft Lens for Android: https://support.microsoft.com/en-us/lens/microsoft-lens-for-android
- vFlat product capabilities: https://www.vflat.com/en
- DocScanner rectification research: https://arxiv.org/abs/2110.14968

## 18. Local Flutter skill usage requirements

The Flutter skills stored under `BookScanner/.agents/skills/` are project implementation instructions. Contributors and coding agents must inspect the applicable `SKILL.md` before performing the related work, use its workflow, adapt examples to BookScanner, and run its required validation. Skill examples are guidance, not code to copy blindly.

| Local skill | Invoke when | Required BookScanner outcome |
|---|---|---|
| `dart-flutter-patterns` | Creating or reviewing Dart code, state, async work, widgets, storage/network access, error handling, or tests | Null-safe idiomatic Dart; immutable/sealed state; lean widget classes; scoped rebuilds; mounted checks after awaits; explicit errors; unit/widget tests with fakes where practical |
| `flutter-apply-architecture-best-practices` | Scaffolding the app, adding a feature, or refactoring dependencies | UI, domain, and data separation; MVVM presentation; repository boundary; platform plugins wrapped as Services; constructor injection; no business/data logic in Views |
| `flutter-navigation` | Implementing or changing transitions, route data, back behavior, shells, guards, links, or navigation tests | Inspect existing routing first; use the smallest suitable routing model; preserve state/back behavior; parse route data safely; test changed routes; run formatter/analyzer/tests |
| `flutter-setup-declarative-routing` | Initial route bootstrap or when BookScanner needs deep links, shareable routes, persistent tab stacks, guards, or scalable URL-based navigation | `MaterialApp.router` and `go_router` configuration where justified; route error screen; typed/validated parameters; platform link configuration and tests only when links enter scope |
| `flutter-setup-localization` | Project initialization and every user-visible string change | `flutter_localizations`, `intl`, `flutter: generate: true`, `l10n.yaml`, ARB resources, generated type-safe access, descriptions/placeholders/plurals, and no hard-coded user-visible strings |
| `flutter-fix-layout-issues` | A layout exception, overflow stripe, unbounded constraint, or responsive-layout failure appears | Diagnose the first constraint error; apply the matching constraint fix; re-run; verify supported screen sizes, orientations, text scales, locales, and RTL |
| `flutter-add-integration-test` | Establishing the test harness, validating a critical user journey, or turning an explored flow into regression coverage | `integration_test/` suite, stable widget keys, repeatable fake/native-adapter fixtures, Android/iOS execution, assertions for user-visible outcomes, and performance traces where needed |

### 18.1 Routing decision for BookScanner

- Start with `go_router` and `MaterialApp.router` because the app has multiple persistent areas and long, resumable workflows. Use a stateful shell only if independent tab stacks are part of the approved UI.
- Use stable project/page identifiers in path parameters for addressable screens and query parameters only for optional view state. Do not pass durable project state solely through `extra`.
- Keep capture substeps local to the capture flow when they should not be externally addressable. Do not create deep links or domain association files until sharing/open-in requirements demand them.
- Preserve unsaved capture state and define deliberate back/cancel confirmation behavior. Add route tests for project resume, export completion, invalid identifiers, and not-found/error handling.

### 18.2 Localization baseline

- Configure localization before the first feature screen so strings never need a later mass extraction.
- English is the template locale. The additional launch locales remain a product decision, but pseudo-localization and right-to-left layout testing are required during development.
- Localize camera guidance, quality warnings, permissions explanations, OCR confidence messages, page counts/plurals, processing states, export errors, privacy consent, and accessibility labels.
- Document/OCR language selection is separate from UI locale and must not be inferred without user control.

### 18.3 Definition of done for Flutter changes

A Flutter task is complete only when the applicable local skills have been followed and:

1. Edited Dart files are formatted.
2. `flutter analyze` passes without newly introduced issues.
3. Relevant unit and widget tests pass.
4. Changed critical journeys have an integration test or a documented reason one is not applicable.
5. New user-facing strings use generated localization accessors.
6. Navigation changes include route/back/error-state validation.
7. Layout is checked at supported compact/large widths, increased text scale, and applicable RTL locale.
8. Flutter feature code remains independent of concrete native scanner providers.

