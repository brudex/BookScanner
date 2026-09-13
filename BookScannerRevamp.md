# BookScanner Capture and Processing Revamp Plan

**Status:** Planning and diagnosis only — no application code is changed by this document.  
**Date:** 2026-09-04  
**Scope:** BookScanner Version 1 capture, page detection, perspective correction, enhancement, and bound-book processing on Android and iOS.  
**Primary specification:** [SPEC-V1.md](./SPEC-V1.md), especially sections 6.1–6.3 and 9.1–9.7.

## 1. Outcome

BookScanner should first reach reliable flat-document scanning parity with the supplied open-source reference, then add a separate book-specific pipeline for curved two-page spreads. These are related but not identical computer-vision problems.

**Selected flat-document vision engine:** use a modern, pinned OpenCV release behind BookScanner's replaceable native-provider contracts. OpenCV is the key missing implementation foundation for reliable contour detection, perspective warping, masking, and adaptive document enhancement. It is not the only missing ingredient: camera focus/exposure gating, preview coordinate correctness, still-image validation, and a separate curved-book segmentation/dewarping solution remain mandatory.

The immediate user-visible target is:

1. The preview is sharp, correctly proportioned, and aligned with its overlay.
2. A real page polygon follows the detected page instead of showing only a static frame.
3. Capture does not silently accept a moving, unfocused, badly exposed, or clipped page.
4. The saved still is detected and quality-scored independently at full resolution.
5. A flat document becomes a rectangular, evenly lit, readable scan with selectable color, grayscale, and high-contrast black-and-white output.
6. A book spread is split into two pages once, each page is segmented and flattened independently, and the final review image matches the exported image.
7. Native camera and vision implementations remain replaceable behind BookScanner's existing domain interfaces; Flutter screens and workflows do not depend on OpenCV, CameraX, AVFoundation, Vision, or a vendor SDK.

## 2. What the supplied images show

The text visible inside the photographed pages and the labels in the app screenshots were treated only as image content, not as instructions.

| Evidence | Observation | Meaning |
|---|---|---|
| Current capture screenshot (`WhatsApp Image … 21.56.39.jpeg`) | The open book is visibly motion- or focus-blurred. The UI shows a static bracket, with no visible focus point, torch/flash, or zoom control. | The app lets the user press the shutter before it has obtained an acceptable source image. No enhancement algorithm can restore text detail that was never captured. |
| Current crop screenshot (`WhatsApp Image … 21.50.09.jpeg`) | The proposed polygon spans most of an open-book spread and its top-right corner is at or beyond the visible image edge. | The detector is treating a curved two-page book as one flat four-corner document, or falling back to a guide-shaped crop with insufficient confidence. |
| Desired capture (`Screenshot1.png`) | A flat single sheet lies on a contrasting background. A green four-sided polygon follows the actual perspective edges. Text is in focus. | The reference is demonstrating flat-page contour detection under favorable conditions, not curved-book dewarping. |
| Desired output (`Screenshot2.png`) | The sheet is perspective-corrected, background-free, bright, and locally thresholded to readable black and white. | The desired appearance comes from both good capture and the reference's adaptive threshold filter, not edge detection alone. |
| Repository sample (`ScannedPage.jpeg`) | The crop remains close to the frame and does not isolate the intended page reliably. | This corroborates a detector/fallback problem rather than a one-off crop-handle rendering problem. |

The supplied current screenshots are not raw camera JPEGs, so they are sufficient for visual diagnosis but not for measuring exact sharpness, crop intersection-over-union, or processing artifacts. The revamp must add raw-capture fixtures and diagnostic metadata so future failures are measurable.

## 3. What the reference Android project actually does

The cloned [Document-Scanner](./Document-Scanner) project is useful as a behavioral reference, but it is an old flat-document scanner, not a complete book scanner.

Its successful path is:

1. Configure continuous camera autofocus and process preview frames when focus is considered settled ([DocumentScannerActivity.java](./Document-Scanner/app/src/main/java/com/myapps/documentscanner/DocumentScannerActivity.java), around lines 835–880 and 917–935).
2. Resize the image to a 500-pixel analysis height.
3. Convert to grayscale, apply a 5×5 Gaussian blur, run Canny edge detection, and find contours ([ImageProcessor.java](./Document-Scanner/app/src/main/java/com/myapps/documentscanner/ImageProcessor.java), around lines 473–512).
4. Sort contours by area, approximate each contour as a polygon, and accept a plausible four-point polygon ([ImageProcessor.java](./Document-Scanner/app/src/main/java/com/myapps/documentscanner/ImageProcessor.java), around lines 280–305).
5. Order the four corners and perform a perspective transform to a rectangle ([ImageProcessor.java](./Document-Scanner/app/src/main/java/com/myapps/documentscanner/ImageProcessor.java), around lines 434–470).
6. For the black-and-white result, use local adaptive thresholding with a 15-pixel neighborhood ([ImageProcessor.java](./Document-Scanner/app/src/main/java/com/myapps/documentscanner/ImageProcessor.java), around lines 364–388).
7. Draw the detected polygon over the live preview after applying its camera-to-display mapping.

### What to reuse and what not to reuse

Reuse the sequence and product behavior as evidence: focused capture, contour candidates, quad scoring, perspective correction, adaptive cleanup, and live geometry feedback. Implement those operations independently with a current OpenCV release rather than attempting to improve the current projection-profile detector indefinitely.

Do not copy its activity, bundled OpenCV 3.1 binaries, or Java source into BookScanner. The project targets Android SDK 23, uses the retired Camera API and obsolete OCR components, and is GPLv3 (`Document-Scanner/LICENSE/GPLv3.txt`). Directly incorporating GPL-covered implementation may impose distribution obligations that must be evaluated by counsel. Implement the ideas independently using current platform APIs and a current, license-reviewed vision dependency.

## 4. Findings in the current BookScanner code

### P0 — the captured source is allowed to be bad

#### 4.1 Manual capture ignores the quality gates

`CaptureViewModel.captureManually()` checks only that a capture is not already running and that the session is open. It does not act on `focusAcceptable`, `motionBelowThreshold`, `exposureAcceptable`, `documentDetected`, or clipped-edge warnings before accepting the shutter ([capture_view_model.dart](./lib/ui/features/capture/view_models/capture_view_model.dart), lines 187–220).

The shutter is disabled only while `capturing` is true ([capture_screen.dart](./lib/ui/features/capture/views/capture_screen.dart), lines 541–617). Therefore the current blurred screenshot is a permitted state, not an unexpected exception.

**Required correction:** manual capture may remain available, but a bad frame must produce one of these explicit behaviors:

- wait briefly for 3A convergence and capture when ready;
- block with a precise instruction such as “Hold still while the camera focuses”; or
- require a deliberate “Capture anyway” override and mark the page `needsRescan` if the saved still fails quality checks.

#### 4.2 Android captures immediately in latency-first mode

The Android controller uses `CAPTURE_MODE_MINIMIZE_LATENCY` and calls `takePicture()` immediately ([CameraXCaptureController.kt](./android/app/src/main/kotlin/com/quizfactor/bookscanner/bookscanner/capture/CameraXCaptureController.kt), lines 111–127 and 167–201). It does not initiate metering for the page, wait for autofocus/auto-exposure convergence, or validate a recent stable-frame window before capture.

This setting is not by itself proof of the blur, but in combination with the missing quality gate it favors exactly the failure visible in the supplied screenshot.

#### 4.3 iOS has the equivalent timing problem

The iOS controller creates default photo settings and captures immediately. It exposes point focus, but does not wait for `isAdjustingFocus`/`isAdjustingExposure` to settle or select explicit photo-quality prioritization ([AVFoundationCaptureController.swift](./ios/Runner/Capture/AVFoundationCaptureController.swift), lines 160–172 and 200–215).

#### 4.4 Focus, flash, and zoom exist below the UI but are not usable in the capture screen

The domain/provider channel already supports focus/exposure point, flash, and zoom. The current ViewModel exposes flash and zoom but not a focus method, and `CaptureScreen` supplies only page count, shutter, and Done controls. There is no tap-to-focus gesture or visible focus indicator ([capture_screen.dart](./lib/ui/features/capture/views/capture_screen.dart), lines 541–617; [capture_view_model.dart](./lib/ui/features/capture/view_models/capture_view_model.dart), lines 250–253).

This is an incomplete integration, not a need to replace the whole Flutter screen.

### P0 — preview geometry and live detection cannot produce the desired overlay

#### 4.5 The preview is stretched rather than rendered with an explicit camera transform

`CameraPreviewView` renders a bare `Texture` in a fill-sized stack ([camera_preview_view.dart](./lib/ui/features/capture/views/camera_preview_view.dart), line 29). The frozen preview deliberately uses `BoxFit.fill` to imitate that stretching ([capture_screen.dart](./lib/ui/features/capture/views/capture_screen.dart), lines 278–321).

There is no canonical preview aspect ratio, crop rectangle, rotation, mirror state, or sensor-to-view transform in the Flutter contract. Consequently, a detected point cannot be guaranteed to land on the same page point the user sees. This will become obvious as soon as the live polygon is restored.

#### 4.6 CameraX use cases are not bound to one viewport

Preview, analysis, and image capture are bound individually without a `ViewPort`/`UseCaseGroup` or an equivalent shared crop/rotation configuration ([CameraXCaptureController.kt](./android/app/src/main/kotlin/com/quizfactor/bookscanner/bookscanner/capture/CameraXCaptureController.kt), lines 91–137).

The three streams can therefore have different aspect crops and transformations. A quad measured in the analysis stream is not automatically a valid quad for the preview or saved JPEG.

#### 4.7 The live detector only returns an axis-aligned rectangle

Android `FrameMath.detectQuad()` reduces the frame to 240 pixels, sums horizontal/vertical edge energy, finds top/bottom/left/right cutoffs, and returns `(left,top)`, `(right,top)`, `(right,bottom)`, `(left,bottom)` ([FrameMath.kt](./android/app/src/main/kotlin/com/quizfactor/bookscanner/bookscanner/capture/FrameMath.kt), lines 106–160). The iOS implementation mirrors this approach.

It cannot represent the trapezoid seen in the desired screenshot and is easily attracted to rows of handwriting, page rulings, a book gutter, or strong internal content.

#### 4.8 The app intentionally hides the detected quad

The capture overlay is a fixed rectangle and only changes color when the analysis reports stability ([capture_screen.dart](./lib/ui/features/capture/views/capture_screen.dart), lines 405–478). This was done because the detector jittered. Hiding the jitter removes user feedback but does not fix detector accuracy.

**Required correction:** produce a scored, smoothed polygon in native analysis; return its transform metadata; render that real polygon. If confidence is low, show a neutral guide and a specific instruction rather than pretending a page was detected.

### P0 — saved-still metadata is stale and can disagree with the image

#### 4.9 Both platforms attach the last preview analysis to the saved still

Android saves the JPEG and returns `lastAnalysis.quad`, `qualityScore`, and warnings without decoding and assessing the captured JPEG ([CameraXCaptureController.kt](./android/app/src/main/kotlin/com/quizfactor/bookscanner/bookscanner/capture/CameraXCaptureController.kt), lines 80–82 and 194–201). iOS does the same ([AVFoundationCaptureController.swift](./ios/Runner/Capture/AVFoundationCaptureController.swift), lines 294–324).

That frame may be older than the shutter, have a different crop/aspect ratio, or precede motion introduced by pressing the button. It should be guidance only.

**Required correction:** persist the original first, bake/record orientation, then run still-image detection and quality scoring against that exact file. Store both live guidance metadata and authoritative still metadata with timestamps and transform provenance.

### P0 — book mode applies flat-page assumptions in the wrong places

#### 4.10 A split book half can be split a second time

`EnhancementRequest.splitOpenBook` defaults to `true`, and its own contract states that already-split book halves should pass `false` ([image_enhancement_provider.dart](./lib/domain/providers/image_enhancement_provider.dart), lines 5–38). However, `ProcessBookSpreadUseCase._buildPage()` enables still detection without setting `splitOpenBook: false` ([process_book_spread_use_case.dart](./lib/domain/use_cases/process_book_spread_use_case.dart), lines 155–165).

This is a concrete pipeline bug. A dark printed column, vertical rule, shadow, or residual gutter in an already-split half can be interpreted as another book gutter, producing an incorrect crop.

#### 4.11 The current “book dewarp” is a documented heuristic, not a robust book model

`DartBookDewarpProvider`:

- looks only in the central 35–65% band for the strongest vertical Sobel-energy column;
- splits the full image with one vertical `copyCrop`;
- fits a single quadratic to correct vertical bowing;
- uses an HSV skin-tone heuristic to flag fingers and does not remove them.

See [dart_book_dewarp_provider.dart](./lib/data/services/scanner/adapters/dart_book_dewarp_provider.dart), lines 14–32 and 117–197.

This is acceptable as a fallback, but it cannot reliably segment curved outer page boundaries, an off-center or diagonal gutter, severe page curl, multiple surface curves, or fingers over text. A printed center rule can also look like a gutter. This is why SPEC-V1 section 9.3 calls for learned left/right page masks and deformation maps for bound books.

#### 4.12 The flat document detector contains book-specific splitting by default

`detectDocumentQuad()` defaults `splitOpenBook` to true, may divide one paper component at a dark central column, and falls back to a fixed capture-guide quad when foreground/background separation exists but corners are uncertain ([page_detection.dart](./lib/data/services/scanner/page_detection.dart), lines 23–63 and 108–134).

This makes uncertainty look like a confident crop. It also mixes two modes that should have distinct policies:

- flat document: detect one page polygon;
- book spread: detect two page masks and a gutter, then rectify each surface.

#### 4.13 The current screenshot may not be traveling through book mode

The code correctly routes a project of `ProjectType.book` to `CaptureMode.bookSpread` and `ProcessBookSpreadUseCase`, which should produce two pages ([capture_view_model.dart](./lib/ui/features/capture/view_models/capture_view_model.dart), lines 153–163 and 207–220). The supplied Adjust Corners image appears to edit one polygon spanning an entire spread.

This is not enough evidence to claim the user selected the wrong mode. The implementation should log and persist the selected project type, requested native mode, pipeline stages, split confidence, and resulting page count so the exact route can be diagnosed from one capture record.

### P1 — enhancement does not match the desired high-contrast result

#### 4.14 Black-and-white uses one global mean threshold

The Dart enhancement adapter converts the page to grayscale, calculates one mean luminance for the entire page, and makes every pixel above or below that mean white or black ([dart_image_enhancement_provider.dart](./lib/data/services/scanner/adapters/dart_image_enhancement_provider.dart), lines 328–360).

The reference uses local adaptive thresholding. Global thresholding is much more sensitive to the gutter shadow, hand shadow, page curvature, yellow paper, and uneven room light visible in the current screenshot.

#### 4.15 The default captured result uses the Original filter

The book pipeline requests `PageFilter.original` ([process_book_spread_use_case.dart](./lib/domain/use_cases/process_book_spread_use_case.dart), lines 155–164). The desired screenshot is a deliberately processed black-and-white document. Product design should decide the default, but the review screen must let the user switch non-destructively among Original, Enhanced Color, Grayscale, and Document B&W. Do not compare Original output with the reference's thresholded output as if they were the same mode.

### P1 — artifact ownership and review consistency are unsafe

#### 4.16 The final dewarped page is stored in a temporary directory

`DartBookDewarpProvider.dewarp()` writes a UUID-named file into `tmpDir` ([dart_book_dewarp_provider.dart](./lib/data/services/scanner/adapters/dart_book_dewarp_provider.dart), lines 71–87). `ProcessBookSpreadUseCase` persists that temporary path as the page's `processedImagePath` ([process_book_spread_use_case.dart](./lib/domain/use_cases/process_book_spread_use_case.dart), lines 168–183).

Temporary cleanup can therefore invalidate a page that the database says is ready.

#### 4.17 The thumbnail and processed image come from different pipeline stages

The thumbnail is generated by enhancement before dewarp, while `processedImagePath` points to the later dewarp output. Page Review prefers the thumbnail. The user may approve an image different from the one used by OCR/export.

**Required correction:** write the final dewarped/enhanced artifact atomically to the page's permanent processed path, then derive the thumbnail from that exact final artifact. Keep the original immutable.

### P1 — current tests can pass while real scans fail

The repository has useful unit and synthetic-corpus tests, but the observed failures are device-, transform-, texture-, focus-, lighting-, and curved-surface-dependent. Passing synthetic tests does not validate:

- preview/analysis/still coordinate agreement on a real device;
- autofocus convergence and shutter-induced motion;
- edge accuracy on ruled notebooks and multi-column documents;
- book gutters competing with printed vertical lines;
- local thresholding under real shadows;
- the exact image shown in review versus OCR/export input.

The revamp needs consented raw-image fixtures plus Android and iOS device tests, not screenshots alone.

## 5. Target architecture

Keep the existing Flutter layering and provider boundaries. They are the strongest part of the current design and already satisfy the replaceability requirement in SPEC-V1 section 9.7.

### 5.1 Canonical, vendor-neutral contracts

Evolve the contracts intentionally so every implementation can return:

- original image path and immutable asset ID;
- width, height, orientation, rotation, and mirroring;
- preview buffer size, displayed content rectangle, and sensor/analysis/still transforms;
- mode (`singlePage` or `bookSpread`);
- one flat-page polygon or two book-page masks plus gutter geometry;
- confidence per geometry result and explicit failure reason;
- sharpness, motion, exposure, glare, clipped-edge, and occlusion metrics;
- provider, adapter, algorithm/model version, options, and timing;
- final artifact paths and checksums.

Do not expose `Mat`, `VNRectangleObservation`, CameraX classes, ML tensors, or vendor-specific errors outside the infrastructure adapter.

### 5.2 Replaceable provider composition

Use the existing interfaces and dependency injection:

- `CaptureProvider`: CameraX/AVFoundation session, 3A, preview, and still persistence.
- `PageDetectionProvider`: a native OpenCV contour implementation for flat pages, with the Dart implementation retained as fallback.
- `ImageEnhancementProvider`: OpenCV perspective warp and document filters, implemented by a native/shared vision adapter, with pure Dart fallback.
- `BookDewarpProvider`: a book-specific segmentation/deformation adapter, with the current heuristic as a capability-limited fallback.

If detection and warp must share a decoded buffer or transform to avoid inconsistencies, add a narrowly scoped `ScanProcessingProvider` facade in the domain layer. Its result must still contain canonical BookScanner models. Selection belongs in `service_locator.dart` or a dedicated provider registry, controlled by platform, capability, feature flag, benchmark result, and fallback policy.

Every concrete adapter must pass the same contract suite. Replacing OpenCV with Apple Vision, a commercial SDK, or a future shared C++ core must not require changes to capture screens, page review, persistence, OCR, or export.

### 5.3 Processing pipelines

#### Flat document

`camera guidance → 3A/quality gate → immutable still → authoritative still detection → confidence decision/manual correction → perspective warp → illumination normalization → selectable enhancement → still quality score → permanent final artifact → thumbnail → OCR/export`

#### Bound book

`book guidance → 3A/quality gate → immutable spread still → left/right page segmentation + gutter → confidence decision/manual split → per-page surface dewarp → per-page enhancement → still quality score → permanent page artifacts/thumbnails → OCR/layout/export`

Do not pass a book spread through the flat-document quad pipeline and do not apply spread splitting to an already-split page.

### 5.4 OpenCV integration and usage instructions

#### 5.4.1 Scope and responsibilities

OpenCV will be the primary engine for flat-document computer vision. It must be used for:

- grayscale/luminance conversion and controlled denoising;
- Canny or equivalent edge extraction;
- morphology used to join broken page boundaries;
- contour and line candidate extraction;
- four-point polygon approximation, ordering, scoring, and validation;
- full-resolution perspective transformation;
- page masking/background exclusion;
- illumination normalization, local contrast, and adaptive black-and-white thresholding;
- blur, glare, exposure, and post-warp quality measurements where OpenCV provides a better implementation than the current custom loops.

OpenCV must not own Flutter navigation, the capture screen, project records, user decisions, OCR schema, or export workflows. CameraX remains responsible for Android capture and AVFoundation remains responsible for iOS capture. OpenCV consumes their analysis buffers and persisted still images.

OpenCV alone does not solve a severely blurred source image and ordinary four-corner processing does not flatten a curved book. Phase 1 camera gating and Phase 4 book segmentation/dewarping therefore remain separate requirements.

#### 5.4.2 Version and dependency policy

1. Select one stable OpenCV release at implementation time, pin its exact version/tag, and record it in provider metadata and the dependency lock/build configuration. Do not use an unbounded or floating version.
2. Use OpenCV 4.5 or later so the library is under Apache 2.0, subject to final dependency/license review. Preserve required notices. See the [official OpenCV license](https://opencv.org/license/).
3. Use only required modules initially: `core`, `imgproc`, and `imgcodecs`. Add other modules only with a measured need. Do not enable `opencv_contrib` or non-free modules by default.
4. Record binary size per ABI before and after integration. Strip debug symbols from release artifacts while retaining symbol files needed for crash diagnosis.
5. Do not copy the reference project's OpenCV 3.1 module or binaries. Do not copy its GPLv3 application source.

OpenCV officially publishes Android and iOS packages for releases; Android artifacts have also been available through Maven Central since OpenCV 4.9. See the [official installation overview](https://docs.opencv.org/4.x/d0/d3d/tutorial_general_install.html) and [Android integration guide](https://docs.opencv.org/4.x/d5/df8/tutorial_dev_with_OCV_on_Android.html).

#### 5.4.3 Proposed native module layout

The following is a proposed structure, not an instruction to expose native types to Dart:

```text
BookScanner/
├── native/scanner_core/
│   ├── include/bookscanner/scan_core.hpp
│   ├── src/flat_page_detector.cpp
│   ├── src/perspective_warper.cpp
│   ├── src/document_enhancer.cpp
│   ├── src/quality_analyzer.cpp
│   └── test/
├── android/app/src/main/cpp/          # JNI adapter to scanner_core
├── android/.../capture/               # CameraX calls scanner_core for live frames
├── android/.../processing/            # path-based still processing adapter
├── ios/Runner/ScannerVision/           # Objective-C++ bridge + Swift adapter
└── lib/data/services/scanner/adapters/ # vendor-neutral Dart channel adapters
```

The preferred production design is one C++ `scanner_core` shared by Android and iOS so both platforms use the same detector, thresholds, corner ordering, warp, and filter behavior. Kotlin/JNI and Objective-C++/Swift wrappers should only convert platform buffers, paths, options, results, and errors.

If shared-core linking blocks the first proof of concept, an Android Kotlin/OpenCV API spike may validate the algorithm. It must not become a second long-lived implementation. Before completing Phase 2, move the proven algorithm and golden tests into the shared core or document and approve a concrete reason not to do so.

#### 5.4.4 Android setup

1. Add the exact approved OpenCV artifact to `android/app/build.gradle.kts`. The official Maven form is conceptually:

   ```kotlin
   val openCvVersion = "<pinned-approved-version>"
   implementation("org.opencv:opencv:$openCvVersion")
   ```

   Resolve the placeholder during implementation after checking supported Android API level, ABI contents, binary size, and shared-C++ linkage. Do not paste an old version from the reference app.
2. Initialize OpenCV once in the native infrastructure layer using the supported local initialization API (`OpenCVLoader.initLocal()` for the official Android package). Expose initialization failure as `capability unavailable`/`provider initialization failed`; do not display provider-owned Android UI or Toasts.
3. Keep CameraX Preview, ImageAnalysis, and ImageCapture. Do not replace CameraX with OpenCV's camera view or the legacy Camera1 API.
4. In `ImageAnalysis.Analyzer`, wrap the Y plane as grayscale input with as few copies as practical, rotate/map according to `rotationDegrees`, downscale, and invoke the live detector on the analysis executor.
5. Never retain an `ImageProxy` after analysis and always close it in `finally`. Keep `STRATEGY_KEEP_ONLY_LATEST` so processing cannot block the capture pipeline.
6. For saved stills, pass a file path and orientation metadata to the native processing adapter. Decode and process off the main thread. Return result metadata and output paths, not pixel arrays, through the Flutter channel.
7. If the Maven AAR cannot be cleanly linked to the shared C++ core, build Android native OpenCV libraries from the same pinned source tag used for iOS and package only supported ABIs. Make that build reproducible in CI rather than committing opaque libraries without provenance.

#### 5.4.5 iOS setup

1. Use the official OpenCV release package or build a pinned `opencv2.xcframework` containing device arm64 and supported simulator architectures. OpenCV's official [`build_xcframework.py`](https://github.com/opencv/opencv/blob/4.x/platforms/apple/build_xcframework.py) builds an XCFramework for selected Apple platforms.
2. Link the framework in the Runner target and add its required privacy/license notices. Do not fetch or build OpenCV during an end user's app launch.
3. Add a narrow Objective-C++ (`.mm`) bridge between Swift and `scanner_core`; do not spread OpenCV headers or `cv::Mat` through Swift application code.
4. In the AVFoundation video-data callback, convert the `CVPixelBuffer` luminance plane to the shared detector input without a JPEG encode/decode cycle. Apply the buffer orientation and preview transform explicitly.
5. Process captured HEIC/JPEG files on a background queue. Normalize orientation before detection and preserve the immutable original.
6. Return the same canonical results, confidence meanings, errors, and provider versions as Android.

#### 5.4.6 Flutter and platform-channel setup

1. Add native OpenCV adapters under the existing infrastructure/data layer; do not import an OpenCV Flutter package into Views or ViewModels.
2. Prefer the existing `PageDetectionProvider` and `ImageEnhancementProvider`. Add a versioned `ScanProcessingProvider` only if one atomic native operation is required to keep detection, warp, and output metadata consistent.
3. Add native channel methods for initialization/capabilities and **path-based still processing**. Live frames must never cross the channel. Live analysis stays inside the native capture adapter and emits only normalized geometry, confidence, quality signals, transform metadata, and timestamps.
4. Register `NativeOpenCvPageDetectionProvider` and `NativeOpenCvImageEnhancementProvider` in the composition layer when supported. Retain the current Dart adapters as explicit fallback providers.
5. Persist `providerName`, adapter version, OpenCV version, algorithm/config version, input artifact ID, output artifact ID, and processing options with each derived page.
6. Surface an unavailable OpenCV provider through capability discovery. Flutter should fall back to manual crop/basic processing without knowing why a particular vendor library is unavailable.

Do not use a generic Flutter OpenCV or document-scanner plugin merely to reduce setup time unless it passes the same architecture, privacy, license, offline, transform, performance, and provider-replacement requirements. A plugin that owns its UI or sends full frames through Dart would undermine the current design.

#### 5.4.7 Flat-page detection algorithm

Implement the live and saved-still detectors from the same core function with different resolution/performance options:

1. Normalize orientation and obtain an 8-bit luminance image.
2. Downscale while preserving aspect ratio. Start benchmarking around a 640–960 pixel longest edge for live analysis and a 1200–1600 pixel longest edge for saved-still detection; tune from measurements rather than hard-coding these as universal values.
3. Apply a small Gaussian or bilateral denoise that removes sensor noise without erasing weak paper edges.
4. Calculate adaptive Canny thresholds from image statistics, with bounded configuration values. The reference's fixed `75/200` thresholds are a baseline fixture, not a universal production setting.
5. Apply a small morphological close only when needed to connect broken page edges.
6. Run `findContours` and optionally a Hough-line fallback for weak/partially occluded boundaries.
7. For each plausible contour, run `approxPolyDP`, retain convex four-point candidates, order corners consistently as top-left, top-right, bottom-right, bottom-left, and reject self-intersections.
8. Score candidates by normalized area, convexity, angle plausibility, edge support, border margin, guide overlap, aspect plausibility, center distance, and temporal continuity. Return the best candidate only above a calibrated confidence threshold.
9. Smooth live points over time and require a dwell period. Clear the polygon when confidence drops rather than freezing a stale green result.
10. Return normalized coordinates plus the exact analysis image dimensions, rotation, crop rectangle, mirror state, timestamp, and confidence.

The fixed capture guide is only framing assistance. It must never become an automatic crop when OpenCV did not find a trustworthy page.

#### 5.4.8 How OpenCV removes the surrounding background

Background removal is the result of geometry plus enhancement, not one OpenCV switch:

1. The chosen contour defines the paper boundary.
2. The four corners are scaled from the analysis image back to the authoritative still-image pixels.
3. Output width and height are calculated from opposing page-edge lengths.
4. `getPerspectiveTransform` and `warpPerspective` map only the page quadrilateral into a new rectangular image. Pixels outside the page polygon are therefore excluded from the output.
5. Any small uncertain border can be filled with white only outside a conservative page mask; never erase pixels inside possible content.
6. Illumination normalization estimates the page background and reduces large soft shadows.
7. Document B&W applies local adaptive thresholding inside the rectified page, making the paper white while preserving locally dark text.

If a reliable polygon is not found, do not manufacture a background-free result. Open manual corner correction over the immutable original and then run the same OpenCV warp/enhancement using the confirmed corners.

For a curved book, replace the four-corner polygon with left/right page masks and deformation maps from the book provider. OpenCV can apply the masks and backward remap, but it cannot infer accurate curved surfaces from the flat-document contour recipe alone.

#### 5.4.9 Perspective correction and enhancement recipes

After the saved-still quad is accepted or manually confirmed:

1. Warp at the source resolution, subject to a memory-safe maximum output dimension.
2. Preserve one lossless or high-quality intermediate during processing; avoid repeated JPEG generations.
3. Produce non-destructive recipes:
   - **Original:** rectified page with no appearance transformation.
   - **Enhanced Color:** illumination normalization, local contrast on luminance, mild denoise, and conservative sharpening.
   - **Grayscale:** normalized grayscale with stroke-preserving contrast.
   - **Document B&W:** normalized grayscale followed by local adaptive thresholding. Benchmark mean/Gaussian adaptive threshold and Sauvola-style thresholding on handwriting, print, shadows, and colored paper.
4. Apply filters after geometric correction so neighborhood sizes and text strokes are evaluated in page space.
5. Calculate quality metrics on both the original still and final rectified output. Enhancement must not turn a failed source into a falsely accepted page.
6. Write the selected final artifact atomically to the page's permanent processed path and derive its thumbnail from that exact file.

#### 5.4.10 Performance, memory, and concurrency

- Target a controlled live-analysis rate rather than processing every camera frame; benchmark 10–15 useful detections per second on low/mid devices.
- Reuse allocated native buffers where safe and rely on C++ RAII for `cv::Mat` ownership. Never retain references to CameraX or AVFoundation buffers after their callback ends.
- Keep full-resolution detection, warp, and enhancement on bounded native worker queues. Limit concurrent pages according to measured peak memory.
- Cancel or supersede obsolete preview work, but never cancel persistence of an already captured immutable original.
- Add timeouts and typed failures for native initialization, decode, detection, warp, write, and cancellation.
- Track P50/P95 live latency, still-processing latency, peak resident memory, binary-size increase, battery, thermal behavior, and crash rate per provider version.

#### 5.4.11 OpenCV verification and rollout

1. Add C++ unit tests for corner ordering, candidate scoring, transforms, and filter behavior.
2. Run the same golden corpus through the Dart baseline and OpenCV provider; generate side-by-side diagnostics and metrics.
3. Add adapter contract tests on both platforms, including provider-unavailable and corrupted-input cases.
4. Initially place OpenCV behind a development feature flag. Support shadow evaluation where the OpenCV result is measured but not shown to the user.
5. Promote it to the default flat-document provider only when Phase 2 accuracy, latency, memory, and artifact-consistency thresholds pass on both platforms.
6. Keep the Dart fallback until the supported device matrix proves native availability and failure handling.
7. Record the OpenCV version and algorithm configuration in `IMPLEMENTATION_STATUS.md`; do not mark device-dependent criteria complete from unit tests alone.

## 6. Phased implementation plan

### Phase 0 — baseline and diagnostics

**Purpose:** make every later comparison reproducible before changing algorithms.

Tasks:

1. Create a consented fixture corpus containing the two current failure patterns plus flat A4/Letter pages, ruled notebooks, white-on-light surfaces, skew, blur, hand shadow, glare, clipped corners, multi-column pages, printed center lines, curved books, off-center gutters, fingers, and right-to-left books.
2. Preserve raw JPEG/HEIC files, not screenshots of the review screen. Remove EXIF location and personal data before committing fixtures.
3. Add a debug capture manifest with device model, OS, lens, focus/exposure state, frame and still dimensions, transform metadata, mode, provider versions, timing, geometry/confidence, quality metrics, and pipeline decisions.
4. Add a debug overlay/export showing candidate contours, selected polygon/masks, confidence, crop transform, and rejection reason.
5. Record current metrics as the baseline; do not tune against only one notebook or phone.

Exit criteria:

- A failure can be reproduced from an immutable input file without reopening the camera.
- One capture manifest proves whether the session was document or book mode and identifies every provider used.
- Baseline measurements exist for accuracy, sharpness rejection, latency, memory, and output readability.

### Phase 1 — camera sharpness and preview-coordinate correctness

**Purpose:** stop feeding unusable or geometrically ambiguous images into the scanner.

Android tasks:

1. Bind Preview, ImageAnalysis, and ImageCapture with one `UseCaseGroup`/`ViewPort`, target rotation, and deliberate aspect policy.
2. Return the actual preview resolution and transformation/crop metadata through a versioned provider contract.
3. Prefer a quality-oriented still mode for document capture after device benchmarking; configure JPEG quality/resolution explicitly and avoid digital zoom by default.
4. Enable continuous AF/AE/AWB where supported. On shutter, meter on the detected page/center, wait a bounded period for 3A convergence, then capture.
5. Support tap-to-focus/expose, focus indicator, torch/flash modes, pinch or stepped zoom, and exposure compensation through vendor-neutral ViewModel methods.
6. Keep the latest-frame timestamp; reject stale analysis metadata.

iOS tasks:

1. Configure continuous autofocus, continuous auto-exposure, subject-area change monitoring, and a quality-prioritized photo path where supported.
2. Define one preview `videoGravity` and export the corresponding metadata-output/device-to-view conversion.
3. Add the same tap focus, exposure, torch, zoom, and bounded convergence behavior exposed through the same Flutter contract.

Flutter tasks:

1. Render the texture at the camera's intended aspect ratio and crop mode rather than stretching it.
2. Centralize `analysis ↔ preview ↔ still` point mapping and unit-test rotations 0/90/180/270, portrait/landscape, cover/contain crop, and mirroring.
3. Make the shutter state explicit: ready, focusing, hold still, low light, glare, edges clipped, processing.
4. For manual capture, wait briefly for readiness; offer an accessible override instead of silently accepting a failed gate.

Exit criteria:

- A checkerboard/corner calibration fixture aligns within 1.5% of the short preview dimension on supported test devices.
- The preview is not visibly stretched.
- Motion-blurred or unfocused stills are rejected or explicitly overridden in at least 95% of the labeled blur corpus.
- The saved still is independently scored; no persisted page inherits only the last preview score.

### Phase 2 — flat-document detection and reference-quality enhancement

**Purpose:** achieve the behavior shown by the reference app on the same class of input.

Detection tasks:

1. Integrate the pinned, license-reviewed OpenCV release following section 5.4, with Android and iOS adapters backed by the shared `scanner_core` where practical.
2. On reduced-resolution preview frames: grayscale, denoise, edge extraction, morphological close where useful, contour/line candidates, convex four-point approximation, and normalized corner ordering.
3. Score multiple candidates using area, convexity, rectangularity, border proximity, angle plausibility, edge support, center/guide overlap, temporal continuity, and confidence—not simply the largest contour.
4. Smooth the selected polygon using a time-aware filter and require a stable dwell window. Do not equate “quad exists this frame” with stability.
5. Draw the real polygon after applying the canonical preview transform. When confidence is below threshold, draw no false green polygon.
6. Re-run detection on the orientation-corrected saved still at a higher analysis resolution; remap to original pixels and use this as the authoritative crop.
7. Remove the fixed-guide fallback as an automatic crop. A guide may be a UI hint, but uncertain detection must enter manual corner correction with a clear confidence state.

Warp and enhancement tasks:

1. Compute output width/height from opposing edge lengths and apply a four-point perspective warp.
2. Add robust illumination/shadow normalization that protects foreground strokes.
3. Add local adaptive thresholding for Document B&W. Benchmark Gaussian/mean adaptive threshold and Sauvola/Wolf methods on the corpus; choose by readability and stroke preservation, not resemblance to one screenshot.
4. Keep Original, Enhanced Color, Grayscale, and Document B&W as non-destructive recipes derived from the immutable source.
5. Add light denoise and conservative sharpening after rectification; never attempt to “sharpen” a severely blurred capture into an accepted page.
6. Persist recipe and provider versions so pages can be regenerated after an adapter upgrade.

Exit criteria:

- On the flat-page corpus, at least 95% of visible corners fall within 2% of the image diagonal, with no content clipped.
- A flat page photographed at perspective becomes rectangular and preserves its expected aspect within 3%.
- Document B&W removes large soft shadows while preserving thin handwriting and printed punctuation on at least 95% of labeled text regions.
- On the same favorable flat-sheet conditions as `Screenshot1.png`, BookScanner produces an output comparable in crop, rectification, and readability to `Screenshot2.png`.
- P95 live analysis stays within the device budget selected in Phase 0 and does not stall the camera UI.

### Phase 3 — repair the existing book pipeline before adding ML

**Purpose:** remove deterministic bugs and make the fallback honest.

Tasks:

1. Set `splitOpenBook: false` for enhancement of already-split halves and add a regression test containing a strong printed center rule.
2. Make book mode explicit from capture through every processing request; reject invalid mode/stage combinations in debug and tests.
3. Replace “strongest central vertical edge” with a multi-signal gutter estimate: dark valley, continuity, page symmetry, outer boundaries, orientation, curvature, and temporal evidence. Preserve manual split correction for low confidence.
4. Crop each half using its own outer-page geometry rather than full-height vertical slicing.
5. Pass the actual detected page bounds/mask into dewarp instead of `Quad.fullFrame`.
6. Write final dewarp output atomically to the permanent processed path, then generate the thumbnail from it.
7. Ensure Page Review, OCR, PDF, Markdown, and DOCX all resolve the same final artifact/version.
8. If fallback confidence is too low, retain the original and label the page for manual split/crop or rescan; never fabricate a successful crop.

Exit criteria:

- Each spread is split exactly once.
- A page with a printed vertical rule is not re-split.
- Temporary-directory cleanup cannot remove a ready page's processed image.
- Thumbnail, full review, OCR input, and export input have matching artifact IDs/checksums.
- Low-confidence spread detection always opens correction or requests a rescan.

### Phase 4 — production book segmentation and dewarping

**Purpose:** solve the curved-book problem that the reference project does not solve.

Tasks:

1. Evaluate at least two replaceable providers against the bound-book corpus:
   - an on-device learned page segmentation/dewarping model with separate Android/iOS runtimes; and
   - a shared C++/OpenCV geometric pipeline as fallback/baseline.
2. Require outputs for left/right masks, gutter centerline, outer boundaries, occlusion mask, confidence, and backward remap/deformation field.
3. Flatten each page independently using backward remapping so curved text baselines straighten without tearing or duplicating content.
4. Flag fingers/occlusions; do not inpaint text unless a separately approved feature has measurable confidence and preserves the immutable source.
5. Handle single visible page, two-page spread, off-center spine, rotated phone, thick binding, pages with illustrations, and right-to-left ordering.
6. Benchmark model size, cold start, per-spread latency, peak memory, battery, thermal behavior, and minimum supported device.
7. Select the provider through capability/configuration, with the repaired heuristic available as a labeled fallback.

Exit criteria:

- At least 90% of the representative book corpus has correct left/right masks and gutter without manual adjustment.
- At least 90% of labeled curved text baselines are materially straighter after dewarp without new clipping/tearing.
- Provider replacement requires composition/configuration and adapter changes only; Flutter capture/review workflows remain unchanged.
- Unsupported devices degrade to manual split/crop and basic correction rather than crash or silently corrupt output.

### Phase 5 — capture UX parity and high-volume book scanning

**Purpose:** make the technically improved pipeline usable for hundreds of pages.

Tasks:

1. Restore opt-in auto-capture only after focus, exposure, motion, edge confidence, and dwell-window tests pass. Make manual capture the safe fallback.
2. Show a stabilized page polygon/masks, focus indicator, flash/torch, zoom, page count, current mode, processing queue, and a thumbnail of the last accepted result.
3. In book mode, show gutter guidance and both page regions; allow an immediate undo/rescan without ending the session.
4. Process pages through a bounded background queue so the camera can resume without exhausting memory.
5. Provide non-color-only feedback, screen-reader labels, haptic/audio capture confirmation, and localized guidance.
6. Add session recovery so an interruption preserves every immutable still and pending processing job.

Exit criteria:

- A user can scan 100 consecutive pages without losing a captured original, leaking temporary artifacts, or exhausting memory.
- Auto-capture never fires during focus/exposure adjustment in the tested device matrix.
- The user can identify and correct the last bad page without leaving the capture session.

## 7. Test strategy

### 7.1 Contract tests

Run the same suite against every implementation of `CaptureProvider`, `PageDetectionProvider`, `ImageEnhancementProvider`, and `BookDewarpProvider`:

- canonical coordinate ordering and normalized ranges;
- orientation/mirroring behavior;
- capability discovery;
- deterministic error translation;
- immutable original ownership;
- permanent output paths;
- provider and algorithm version metadata;
- cancellation and retry behavior;
- fallback without Flutter feature changes.

### 7.2 Golden-image metrics

For each fixture store human-reviewed annotations and calculate:

- corner error and polygon/mask IoU;
- false-positive/false-negative page detection;
- content clipping rate;
- split/gutter error;
- dewarp baseline curvature before/after;
- sharpness and blur classification precision/recall;
- glare/shadow coverage;
- OCR character/word error rate before and after enhancement;
- SSIM or perceptual change inside protected text strokes;
- latency, memory, output size, and failure type.

Avoid a single composite “quality score” as the only gate. A page can be sharp but clipped, bright but glared, or well-cropped but unreadable.

### 7.3 Device matrix

At minimum test:

- one low/mid Android device and one modern high-resolution Android device;
- one older supported iPhone and one current iPhone;
- portrait and landscape;
- indoor low light, bright light, and mixed shadow;
- flash off/auto/on where supported;
- flat pages and bound books.

Use integration tests for permission flow, focus interaction, manual/auto capture, document/book mode routing, interrupted-session recovery, manual crop/split correction, review artifact consistency, and export.

## 8. Prioritized backlog

| Priority | Work item | Why first |
|---|---|---|
| P0 | Raw fixture capture and diagnostic manifest | Prevents guess-and-check tuning and proves which route/provider failed. |
| P0 | Preview/analysis/still transform contract | All live polygons and still crops depend on correct coordinates. |
| P0 | 3A convergence, quality-aware shutter, authoritative still scoring | The visible blur must be stopped at the source. |
| P0 | Pinned OpenCV native/shared-core integration | Supplies the missing production primitives without coupling Flutter to a vendor. |
| P0 | OpenCV flat-page contour detector plus stabilized live polygon | Required to reproduce the reference capture behavior. |
| P0 | OpenCV perspective warp plus local adaptive Document B&W | Required to reproduce the reference output behavior. |
| P0 | Disable second split of book halves | Concrete current bug with direct crop impact. |
| P1 | Permanent final artifact and regenerated thumbnail | Prevents review/export mismatch and later data loss. |
| P1 | Improved classical gutter/page geometry | Makes the non-ML fallback usable and measurable. |
| P1 | Learned book segmentation/dewarp adapter evaluation | Needed for true curved-book quality; the reference does not provide it. |
| P2 | Opt-in auto-capture and long-session UX | Valuable only after the readiness signals are trustworthy. |

## 9. Decisions required before implementation

1. **Vision implementation:** adopt a current, pinned OpenCV 4.5+ shared/native adapter as the primary flat-document provider, subject to binary-size, performance, and license review. Keep the domain contracts implementation-neutral so OpenCV can still be replaced.
2. **Book model:** select only after a benchmark on the agreed book corpus; do not choose by demo screenshots alone.
3. **Default filter:** recommended default is Enhanced Color for handwriting/books and Document B&W for printed loose documents, with non-destructive switching in review.
4. **Bad manual capture:** recommended behavior is a short automatic wait followed by an explicit warning and “Capture anyway,” never silent acceptance.
5. **GPL reference:** treat the cloned repository as study material unless the product intentionally accepts GPL distribution obligations after legal review.

## 10. Definition of done

The revamp is complete when all of the following are true:

- The same favorable flat-page scene used by the reference produces a sharp live view, accurate stabilized polygon, correctly rectified page, and readable local-threshold output on Android and iOS.
- A blurred page like the supplied current capture cannot be silently saved as ready.
- A two-page curved book never goes through the single-flat-page path as one quad.
- A book spread is split once, flattened per page, and stored permanently.
- Manual corner and gutter correction remain available when confidence is low.
- The review thumbnail, reviewed full image, OCR input, and exported image are the same versioned artifact.
- The published accuracy and performance thresholds pass on the fixture corpus and device matrix.
- Native provider swaps pass contract and golden tests without changes to Flutter screens, navigation, project persistence, OCR review, or export business rules.
- The selected OpenCV version, build provenance, enabled modules, licenses/notices, algorithm configuration, and adapter version are recorded and reproducible for Android and iOS.
- Dependency licenses, privacy behavior, binary size, supported OS/device levels, and fallback behavior are documented before release.

## 11. Recommended implementation sequence

Do not begin with book ML or a wholesale rewrite. Implement in this order:

1. Phase 0 diagnostics, real raw-image corpus, and an OpenCV dependency/build spike on Android and iOS.
2. Phase 1 focus/exposure/capture gating and coordinate correctness.
3. Phase 2 shared OpenCV flat-document contour detection, warp, and adaptive enhancement.
4. Phase 3 deterministic book-pipeline fixes and artifact consistency.
5. Phase 4 provider benchmark and production book dewarping.
6. Phase 5 auto-capture and high-volume UX.

This sequence separates source-image problems from detector problems, flat-page problems from bound-book problems, and algorithm quality from Flutter integration. It also preserves the replaceable native-provider design already established by SPEC-V1 and the current codebase.
