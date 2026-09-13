# BookScanner Implementation Status

Living traceability document mapping SPEC.md requirements to implementation
status, source files, tests, and verification evidence. Updated after every
vertical slice. Nothing here is marked "done" unless it has been run and
observed working, not just written.

**Last updated:** 2026-09-04 (scanning revamp ready for physical-device
validation). Android pins `org.opencv:opencv:4.11.0` and runs Canny/contour
live+still detection in Kotlin (`OpenCvScanEngine`), with Dart
contour/enhance/dewarp as fallback. Preview is letterboxed (not stretched).
Still capture waits for AF/AE, re-detects the saved JPEG, and does not reuse
preview geometry. Uncertain detections return null (no `Quad.captureGuide`
auto-crop). Book halves use `splitOpenBook: false`; dewarp writes under
`processed/`. Live camera / overlay / AF-wait / still re-detect are 🟡 —
not marked ✅ until a physical-device pass. `flutter analyze` clean;
`flutter test` 227/227 passing. Android `./gradlew :app:testDebugUnitTest`
did not finish this session: host RAM dropped to ~57MB free and the Kotlin
compile stalled (do not treat JVM tests as green). iOS OpenCV xcframework is
not linked (Vision plugin reports unavailable → Dart fallback); iOS still
re-detects via FrameMath on the saved JPEG.
**Environment verified in:** macOS 26.6.2 (darwin-arm64), Flutter 3.38.7,
Xcode 26.6, Android SDK 36.1, Android emulator `Medium_Phone_API_36.1`
(API 36, virtual-scene back camera), iOS Simulator `iPhone 17 Pro` (iOS
26.5, no camera hardware — Apple does not provide one in Simulator), and a
**real physical Android device** (`S200`/`M24P`) used in earlier sessions.
No physical iOS device available — see "Known blockers" at the end.

## Legend

- ✅ Implemented and verified (test passed and/or observed working on-device)
- 🟡 Implemented, not yet independently verified
- ⛔ Not started
- 🚫 Blocked by external dependency (documented below)

---

## 1. Architecture and Phase 0 foundation (SPEC 9, 18)

| Item | Status | Evidence |
|---|---|---|
| Flutter project scaffold (Android + iOS) | ✅ | `flutter create`, builds and runs on Android emulator |
| Layered architecture: `data/`, `domain/`, `ui/` per SPEC 9.1.1 | ✅ | Directory tree matches spec exactly |
| MVVM: lean Views, ChangeNotifier ViewModels | ✅ | `lib/ui/features/*/view_models/*.dart` |
| Repository pattern | ✅ | `lib/domain/repositories/*.dart` (interfaces), `lib/data/repositories/*_impl.dart` |
| Provider contracts (Capture/PageDetection/ImageEnhancement/BookDewarp/Ocr/DocumentExport) | ✅ | `lib/domain/providers/*.dart` |
| Composition root / DI (no Flutter feature imports vendor SDKs) | ✅ | `lib/ui/core/di/service_locator.dart`; verified via `flutter analyze` that no `ui/features/**` file imports CameraX/AVFoundation/platform channels directly |
| go_router routing | ✅ | `lib/routing/app_router.dart`; verified via on-device navigation (Library → New Scan → Capture → Review) |
| Localization (flutter_localizations + ARB, English template) | ✅ | `lib/l10n/app_en.arb`, generated accessors used throughout; verified strings render on-device |
| Local relational DB (sqflite) | ✅ | `lib/data/services/local/database_service.dart`; 6 tables, all repositories covered by unit tests against a real SQLite engine (`sqflite_common_ffi`) |
| Provider/adapter/model versioning persisted with artifacts | ✅ | `ProviderInfo` + `StageRecord` stored per page/pipeline stage |
| Capability discovery | ✅ | `ScannerCapabilities`, queried by `CaptureViewModel` before assuming a feature exists |
| Contract tests runnable against any adapter | ✅ | `test/data/scanner/capture_provider_contract_test.dart` is adapter-agnostic; currently exercised against `FakeCaptureProvider` |

## 2. Native Android capture (SPEC 9.1, 9.2) — task 5

| Item | Status | Evidence |
|---|---|---|
| Kotlin plugin registered via `MainActivity` (switched to `FlutterFragmentActivity` for `LifecycleOwner`) | ✅ | `android/.../MainActivity.kt`, `capture/CapturePlugin.kt` |
| CameraX Preview bound to Flutter `Texture` (no vendor preview widget) | ✅ | `CameraXCaptureController.bindPreviewSurface`; **visually confirmed on-device**: emulator's virtual-scene camera streams live through the Flutter UI |
| ImageAnalysis with `STRATEGY_KEEP_ONLY_LATEST`, every `ImageProxy` closed | ✅ | `CaptureAnalyzer.analyze` closes in a `finally` block |
| Classical edge/blur/exposure/motion analysis (Kotlin) | ✅ | `FrameMath.kt` — Sobel edge energy projection profile, Laplacian-variance sharpness, luminance exposure, frame-diff motion |
| Full-resolution still capture via `ImageCapture` | ✅ | `CameraXCaptureController.captureStill`; **verified on-device**: produces a real JPEG under app-private `filesDir/captures/` |
| Manual shutter | ✅ | Verified on-device: single tap → exactly one persisted page |
| Auto-capture with stability gates | ✅ | `CaptureViewModel._onAnalysis` |
| Auto-capture duplicate-avoidance ("avoids duplicates during page turns," SPEC 17.3 gate 2) | ✅ | **Bug found and fixed via on-device testing**: initial version re-fired every ~600ms on a static scene (no re-arm guard); fixed with an edge-triggered `_awaitingSceneChange` flag that requires an unstable frame before re-arming. Verified: single stable scene now yields exactly 1 capture, not a runaway sequence. |
| Flash/torch, zoom, tap-to-focus/expose | ✅ (code) / 🟡 (untested — emulator has no physical flash/zoom hardware to exercise) | `CameraXCaptureController` |
| Capabilities reporting (`hasFlash`, `supportsZoom`) | ✅ | `CapturePlugin.handleCapabilities` |
| Shutter sound on capture | 🟡 (fixed, redeploying) | **Real gap, user-reported.** Unlike iOS (`AVCapturePhotoOutput` plays the system shutter sound automatically as part of photo capture — no app code involved), CameraX's `ImageCapture.takePicture` is silent by default; nothing gave audible feedback that a capture actually happened. Added `MediaActionSound` to `CameraXCaptureController`, played at the moment `takePicture` is triggered in `captureStill()` (not after the slower save/analysis pipeline finishes, to match a real shutter's timing), released in `shutdown()`. Not yet re-verified on-device as of this entry. |
| Platform-channel contract (method + event channel, versioned, stable error categories) | ✅ | `CaptureContract.kt` mirrors `scanner_channel_contract.dart` |
| Camera permission manifest + runtime flow | ✅ | `AndroidManifest.xml` (`CAMERA`, `USE_BIOMETRIC`, `READ_MEDIA_IMAGES`); verified rationale screen shows when denied, capture screen unlocks when granted |
| Responsiveness during background processing (SPEC 11) | ✅ | **ANR bug found and fixed via on-device testing**: initial enhancement/detection/duplicate-hash pipeline ran synchronously on the Dart UI isolate; a rapid multi-capture burst produced a full Android ANR ("bookscanner isn't responding") dialog. Fixed by moving all heavy `package:image` work (crop/rectify/filter/thumbnail, edge detection, perceptual hashing) to background isolates via `compute()`. Verified: `flutter analyze` clean, full unit suite green, rebuilt and reran on-device without an ANR for a single-capture flow. |
| Sustained rapid-fire burst capture on emulator | 🚫 | A 5-tap-in-1.5s burst test could not be cleanly verified in this session — GC pauses in the 8-12s range indicated the **host machine** (not the app) was under severe memory pressure after ~5 hours of continuous rebuild/relaunch cycles (~76MB free host RAM at the time). This needs re-verification in a fresh session before being marked done. |
| Capture resolution bounded to a sane still-image size | 🟡 (fixed, redeploying) | **Real bug found on the first physical-device test pass, session 4.** `CameraXCaptureController.open()` built `ImageCapture` with no `ResolutionSelector`, so on real hardware with a high-megapixel sensor CameraX chose its raw maximum — observed `StreamSpec{resolution=11584x8688...}` in the device's own logcat, ~100MP. Every capture then had to run `BitmapFactory.decodeFile` (native side, for quality-analysis) and the full pure-Dart perspective/crop/enhancement pipeline (`DartImageEnhancementProvider`, no hardware acceleration) against that image — the shutter button's spinner effectively never resolved. SPEC 9.2's "full-resolution still" was never meant to mean "the sensor's unbinned absolute maximum"; fixed by adding a `ResolutionSelector` targeting ~4032x3024 (~12MP, comfortably enough for OCR/print), `ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER`. Not yet re-verified on-device (rebuild in progress as of this entry) — do not mark ✅ until a real shutter tap on this device completes in reasonable time. |

## 3. Native iOS capture (SPEC 9.1, 9.2) — task 6

| Item | Status | Evidence |
|---|---|---|
| Swift plugin registered via `AppDelegate` | ✅ | `ios/Runner/AppDelegate.swift` calls `CapturePlugin.register(with:)`; files added to the Xcode project programmatically via the `xcodeproj` Ruby gem (`PBXBuildFile`/`PBXFileReference`/`PBXGroup`/sources build phase — creating files on disk alone does not make Xcode compile them) |
| `AVCaptureSession` + `AVCaptureVideoDataOutput` bound to a Flutter `Texture` | ✅ | `AVFoundationCaptureController.swift` / `CaptureTexture` (`FlutterTexture` protocol, `copyPixelBuffer()` backed by the latest video-data-output `CVPixelBuffer`) — same texture-bridging technique used by Flutter's own official `camera` plugin |
| Serial analysis queue, always-discards-late-frames (SPEC 9.2) | ✅ | `videoDataOutput.alwaysDiscardsLateVideoFrames = true` + dedicated `analysisQueue` |
| Classical edge/blur/exposure/motion analysis (Swift) | ✅ | `FrameMath.swift` — deliberately mirrors the Kotlin/Dart algorithms line-for-line (Sobel projection profile, Laplacian-variance sharpness, luminance exposure, frame-diff motion) so quality thresholds behave the same across all three implementations |
| Full-resolution still capture via `AVCapturePhotoOutput` | ✅ | `AVFoundationCaptureController.captureStill`, persists to app-private `Documents/captures/` |
| Flash/torch, zoom, tap-to-focus/expose | ✅ (code) / 🚫 (untested — no camera hardware in Simulator to exercise) | |
| Capabilities reporting (`hasFlash`, `supportsZoom`) | ✅ | `CapturePlugin.handleCapabilities` maps 1:1 to the Android/Dart shape |
| Platform-channel contract (method + event channel, versioned, stable error categories) | ✅ | `CaptureContract.swift` mirrors the Kotlin and Dart contracts exactly |
| Camera/photo-library/Face ID usage-description strings | ✅ | `Info.plist`: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSFaceIDUsageDescription` |
| iOS deployment target | ✅ | Bumped from 13.0 → 15.0 in both `project.pbxproj` and `Podfile` — `file_picker`'s current version requires iOS 14+; this was a real build-blocking issue, not speculative |
| Builds for iOS Simulator | ✅ | `flutter build ios --simulator --debug` succeeds |
| Runs on iOS Simulator | ✅ | Booted `iPhone 17 Pro` (iOS 26.5), `flutter run`, confirmed Library screen renders identically to Android |
| Cross-platform integration test (Library → New Scan → Capture) | ✅ | `integration_test/capture_flow_test.dart`, passing on **both** the iOS Simulator and the Android emulator — see §12 |
| Real camera preview/capture on physical iPhone hardware | 🚫 | **Cannot be verified in this environment.** The iOS Simulator has no camera device at all — AVFoundation returns no capture device, so `AVFoundationCaptureController.configureSession` would throw `CaptureError.unsupportedDevice` if a session were opened without camera permission being meaningfully grantable. This is an inherent Simulator limitation, not a code gap; requires a physical iPhone to close out. |

### Bug found and fixed while building/verifying this (via the new cross-platform integration test)

`ScannerPlatformChannel._invoke<T>` (the shared Dart Service wrapping *both*
the Android and iOS method channel) treated **any** null method-channel
result as an error. That's correct for calls that must return real data
(`capabilities`, `openSession`, `captureStill`), but wrong for void commands
(`closeSession`, `setFlashMode`, `setZoom`, `setFocusAndExposurePoint`) —
native code answering with `result.success(null)` for a void command is the
*expected* success case, not a failure. Concretely, this meant **every**
`closeSession()` call on a real device/simulator threw a spurious
`ProviderException`, which silently aborted the "Done → close session →
navigate to Review" flow (explaining an earlier on-device observation in
session 1 where tapping "Done" didn't appear to navigate — at the time this
was assumed to be a wrong tap coordinate; it was actually this bug).
Fixed by splitting `_invoke` into `_invoke<T>` (require non-null) and a new
`_invokeVoid` (null is success) in `scanner_platform_channel.dart`. Verified
by extending `capture_flow_test.dart` to tap "Done" and assert real
navigation to the Review screen — passes on both platforms now.

**Product decision not yet made and out of scope for now:** no Apple
Developer signing identity is configured in this environment, so
device-only/TestFlight distribution builds remain untested.

## 4. Document capture flow + processing pipeline — task 7

| Item | Status | Evidence |
|---|---|---|
| Capture screen: permission flow, live preview, warnings banner, shutter, page counter | ✅ | `lib/ui/features/capture/`; verified on-device |
| Page detection (classical Dart + native OpenCV still path) | 🟡 (unit-tested; live OpenCV overlay not yet seen on a physical device this session) | Dart `page_detection.dart` v2.3.0 returns null for uncertain/non-quad paper (no `Quad.captureGuide` auto-crop). Android `OpenCvScanEngine` (OpenCV 4.11.0) runs Canny/contours on live luma and the saved still. iOS Vision plugin reports unavailable until the xcframework is linked; still re-detect uses FrameMath on the JPEG. Tests: L-shape → null; native provider falls back to Dart when the plugin is missing. |
| Perspective correction / crop | ✅ (engine + auto-detect path unit-tested) / ✅ (manual 4-corner UI) | `DartImageEnhancementProvider._rectify` via `img.copyRectify` (true 4-point perspective map, destination sized to the quad's own edge lengths). **Session 5:** auto-detect now feeds a real perspective quad into this warp, so a photographed page is trimmed to its edges and the background is dropped — chained in `pipeline_corpus_test.dart`'s skew case (output corners are page content, not the dark background). Manual 4-corner UI in §4a remains for correction when auto-detect misses. Engine tests in `dart_image_enhancement_provider_test.dart` (background removed >98%, 15° skew warps flat, output preserves the quad's aspect ratio). |
| Filters (original/enhanced/grayscale/B&W/photo) | ✅ | `_applyFilter` in the enhancement provider; UI: `FilterAdjustmentScreen`'s `ChoiceChip` row, entered from Page Review's new "Filter & adjust" popup-menu action. `CapturePageUseCase.reprocessPage` already threaded `filter` end-to-end before this session — the gap was UI-only, confirmed by reading the use case first rather than assumed. |
| Brightness/contrast/sharpness adjustment | ✅ | `FilterAdjustmentScreen`'s 3 `Slider`s, same screen as above. Live preview is a deliberate GPU-side `ColorFilter.matrix` approximation (grayscale/B&W/brightness/contrast), not pixel-identical to the real `package:image` pipeline that only runs once on Save — documented in `_colorMatrixFor`'s doc comment, not hidden. Unit-tested (`test/ui/filter_adjustment_view_model_test.dart`) and widget-tested (`test/ui/filter_adjustment_screen_test.dart`). |
| Shadow/stain flattening | ✅ | illumination-normalization via blurred-background division; behavior now also covered by `test/data/scanner/dart_image_enhancement_provider_test.dart` (previously untested provider) and `test/pipeline_corpus/pipeline_corpus_test.dart`'s "shadows" corpus entry |
| Quality scoring + rescan flagging | ✅ | Laplacian-variance sharpness → `PageStatus.needsRescan` below 0.35. **Documented characteristic, made explicit by new tests**: the score is purely a blur/sharpness proxy with no exposure/luminance term at all — a dim-but-crisp image scores as well as a bright-but-crisp one, and a "low light" capture only scores low because real-world low light also tends to be blurry/noisy, not because darkness itself is penalized. See `dart_image_enhancement_provider_test.dart`'s "low light" group. |
| Background isolate processing | ✅ | see ANR fix above |
| Detection-provider failure fallback (SPEC 9.7: "A provider failure ... may fall back to ... without losing the user's confirmed source image") | ✅ | Crop finding now runs inside `enhance(detectCrop: true)` and never throws out of the isolate job. A throwing `PageDetectionProvider` is unused on the capture path; `processCapture`/`replacePage` still persist the original still. Unit-tested in `test/domain/capture_page_use_case_test.dart`; integration test `integration_test/provider_fallback_test.dart` still covers the end-to-end save. |
| `CaptureViewModel` disposed-while-capturing crash | 🟡 (fixed, redeploying) | **Real crash found on the same physical-device test pass, session 4** (in `flutter_run` logcat, not from a written test): `E/flutter: Unhandled Exception: A CaptureViewModel was used after being disposed`, thrown from `notifyListeners()` inside `captureManually`'s `finally` block, stack-traced to `capture_view_model.dart:215`. Root cause: the user navigated away from the Capture screen (disposing its `CaptureViewModel`) while a shutter tap was still mid-pipeline; `dispose()` cancels the analysis subscription but has no way to cancel an already-in-flight `captureManually()` call, so it completed afterward and called `notifyListeners()` on a disposed `ChangeNotifier`, which asserts in debug builds. Fixed with a `_disposed` flag set in `dispose()` and a `_notify()` helper (replacing every direct `notifyListeners()` call in the class) that no-ops once disposed. Regression test added: `capture_screen_test.dart`'s "captureManually completing after the view model is disposed does not throw" gates `captureStill()` on a `Completer`, calls `dispose()` while the capture is still awaiting it, then completes the gate and asserts the capture future still resolves without throwing. Not yet re-observed live on-device as of this entry (rebuild in progress). |
| Capture framing guide on the camera preview (SPEC 9.3: "Return normalized corner coordinates and overlay geometry to Flutter; apply the platform camera-preview transform before drawing guidance") | 🟡 (redesigned per on-device feedback, redeploying) | **Real gap, not previously built at all** — only the text warning banner rendered before this session, no visual framing aid at all. First attempt tracked `FrameAnalysis.quad` live (a polygon following the detector frame-to-frame); **the resolution/crop/dispose fixes above were confirmed working on-device via a real screenshot** (capture no longer hung, blur warning rendered correctly) — and that same screenshot showed the live-tracking outline visibly wobbling, which the user correctly called out as worse than a still target. Replaced with `_CaptureFrameGuide`/`_CaptureFrameGuidePainter` (key `captureFrameGuide`): a fixed corner-bracket rectangle (6%/8% insets) the user aligns the *phone* to, matching TapScanner/most scanner apps, still colored green/white by the live `cornersStable` signal so it gives feedback without moving. Widget-tested (`capture_screen_test.dart`: present immediately on preview-up, unaffected by an incoming analysis frame) — the redesigned version itself not yet seen on-device as of this entry. |
| Shutter only tappable once the capture session is actually open | ✅ | **Bug found via `integration_test/book_scan_session_test.dart` (see §12), not just written to spec.** `CaptureViewModel.initialize()` calls `notifyListeners()` with `permissionState == granted` *before* `await _openSession()` resolves, so `CaptureScreen` rendered a live, tappable shutter button while `_sessionOpen` was still `false`; tapping it then hit `captureManually`'s `if (_capturing \|\| !_sessionOpen) return const [];` guard and silently no-oped -- no error, no capture, no feedback. First surfaced as an integration test failure (page count stayed at 0 after two shutter taps) that looked environmental at first (see the emulator-restart note in §12) but reproduced identically on a freshly restarted, healthy emulator, which is what pointed at a real race rather than instability. Fixed in `capture_screen.dart` by adding a `!_viewModel.sessionOpen` gate (in `_buildCaptureUi`, key `captureSessionOpening`) that shows a spinner instead of the shutter until the session is confirmed open. Locked in by a new widget test in `test/ui/capture_screen_test.dart` that holds `openSession()` open via a `Completer` and asserts the shutter is absent until it's released. |
| Auto-capture disabled — capture is manual-shutter-only | ✅ (deliberate SPEC 17.3 deviation) | **Real on-device UX problem, user-reported and confirmed via a screenshot from the same test pass.** SPEC 17.3's auto-capture (fire once a frame holds every quality gate for a ~600ms stable window) used the exact same `_capturing`/spinner UI state as a manual capture, so the shutter visibly locked out and started spinning on its own while the user was still lining up the shot -- indistinguishable from the app being unresponsive, and it took control away from the user mid-session. Removed the triggering logic entirely from `CaptureViewModel._onAnalysis` (still records `_latestAnalysis` for the warning banner and the capture frame guide's color) and the now-`auto`-param-free `captureManually()`. Regression test in `capture_screen_test.dart`: 5 consecutive "all gates satisfied" analysis frames plus 1s of elapsed time produce zero captured pages -- only a manual shutter tap does. |
| Back navigation from Page Review to the project list (Library) | ✅ | **Real bug, user-reported ("not able to go back to the list of scans page").** Root cause: `NewScanSheetRoute._createAndGo` and `CaptureScreen`'s "Done" handler both used `context.go(...)`, which replaces the *entire* go_router location stack rather than pushing onto it -- Library (and, for the "Add page" re-entry point, the prior Page Review instance) was being stripped out of the back stack, so Page Review's `AppBar` had nothing left to pop back to. Fixed by switching both to `context.pushReplacement(...)`: each replaces only the screen whose job just finished (the mode picker; the just-closed Capture session) while leaving whatever was already beneath it intact, so the back button correctly returns to Library (or, for "Add page," the previous Review instance) either way. |
| Post-capture "Name this scan" dialog | ✅ | **New feature, user-requested.** `NewScanSheetRoute` seeds every new project with a generic mode-based title ("Document"/"Book") and there was no way to rename it until much later (Library's `renameProject` had no UI wired to it at all -- see §5/§11). Added a modal shown when "Done" is tapped on a normal (non-rescan) capture session: `_NameScanDialog` in `capture_screen.dart`, a `TextField` pre-filled with `DateFormat('MM-dd HH:mm').format(DateTime.now())` (e.g. "09-01 14:23"), Cancel/Save. Save calls the new `CaptureViewModel.renameProject(title)` (delegates to `ProjectRepository.renameProject`) before navigating to Review; Cancel just keeps the generic default and navigates anyway -- a name is always present either way, never blank. Unit-tested (`renameProject delegates to the project repository`) and widget-tested (dialog appears on Done, pre-filled value matches the timestamp format) in `capture_screen_test.dart`; all 5 integration test files that tap "Done" updated to accept the new dialog (tap `captureNameSaveButton`) before it, since it now blocks the old immediate navigation. |
| Frozen-frame + loading indicator during per-capture processing | ✅ (unit-tested; freeze-on-click overlay not yet seen on device this session) | `_capturing` is set before `await captureStill()`. Until the JPEG path exists, `CaptureScreen` dims the live preview (`captureShutterScrim`). Once the file is ready, `_FrozenCapturePreview` takes over as before. ViewModel test: capturing is true while `captureStill` is still gated. |
| Frozen-frame zoom-to-guide animation | ✅ | **New feature, user-requested** ("animate to focus on the content within the guides like in TapScanner...indicates to the user content outside the guides will be ignored"). `_FrozenCapturePreview` now runs a `TweenAnimationBuilder` (400ms, `Curves.easeOutCubic`) that scales the frozen image up around its center so the fixed frame guide's bounded region ends up filling the preview -- a pure symmetric zoom, no panning needed, since the guide's insets (`_guideHorizontalInset`/`_guideVerticalInset`, now shared top-level constants instead of duplicated private ones so the painter and this animation can't drift apart) are symmetric and the guide is therefore always centered. Live and frozen previews now use letterboxing (`AspectRatio` +
`BoxFit.contain`) so the camera is not stretched; overlay math lives in
`preview_layout.dart`. Not yet re-seen on a physical device this session. |
| Per-capture pipeline latency / still quality | 🟡 (code + unit tests; not re-timed on device this session) | Android still capture uses `CAPTURE_MODE_MAXIMIZE_QUALITY`, waits for AF/AE, and re-detects the saved JPEG via OpenCV (not last preview analysis). iOS waits for 3A and re-detects via FrameMath on the JPEG. Dart enhance still shares one isolate decode. |

### 4a. Manual four-corner crop correction (SPEC 6.2, SPEC 12 acceptance criterion) — task 16

✅ **Implemented and verified on-device (Android emulator).** Closes the SPEC
12 acceptance criterion: "Given a rectangular document photographed at an
angle, the saved page is cropped and perspective-corrected, and the user can
manually adjust all four corners."

| Item | Status | Evidence |
|---|---|---|
| `CropCorrectionViewModel` (load page, decode intrinsic image size, drag/clamp corners, reset-to-full-frame, reset-to-detected, apply) | ✅ | `lib/ui/features/page_review/view_models/crop_correction_view_model.dart`; 6 unit tests in `test/ui/crop_correction_view_model_test.dart`, all passing |
| `CropCorrectionScreen` (letterboxed image via `applyBoxFit`, draggable corner handles, quad overlay, auto-detect/reset actions, Cancel/Save) | ✅ | `lib/ui/features/page_review/views/crop_correction_screen.dart`; 2 widget tests in `test/ui/crop_correction_screen_test.dart`, all passing |
| Route + entry point from Page Review (tap row or popup-menu "Crop") | ✅ | `AppRoutes.cropCorrection` in `lib/routing/app_router.dart`; wired in `page_review_screen.dart` |
| Apply persists `cropPoints` and re-runs enhancement for just that page | ✅ | `CapturePageUseCase.reprocessPage`; unit-tested and confirmed on-device (see below) |
| **On-device verification (Android emulator, real captured pages, not synthetic)** | ✅ | Captured real pages end-to-end, opened Page Review, tapped into a page, dragged the top-left handle with `adb shell input swipe` — only that corner moved, matching unit-tested behavior. Tapped Save; screen navigated back to Review pages (confirming `apply()` completed without error). Re-opened the same page's crop screen and confirmed the dragged corner position was reloaded from persisted storage — proves the crop is actually written to and read back from the repository, not just held in transient view-model state. |
| `flutter analyze` / full test suite | ✅ | Clean; 60/60 tests passing after adding the 8 new tests for this feature |

**Environmental note, not a product bug:** during this on-device
verification, a single capture appeared to hang indefinitely (shutter
spinner never resolved, no exceptions in `logcat`). Investigation showed
severe ART GC churn (pause times up to ~16s, "Suspending all threads took:
786ms+") and host `vm_stat` showing only ~61MB free RAM — the same
host-resource-exhaustion signature documented in §2/§3 for session 1,
here recurring on a freshly-restarted emulator because of a heavily loaded
host (many Chrome/Cursor/Xcode-toolchain processes competing for RAM
alongside the emulator's qemu process). Waiting it out (rather than
treating it as a code defect) let the capture and every subsequent
interaction complete correctly. Also incidentally confirmed: the app has
an auto-capture-on-stable-frame behavior (pages accumulated on their own
while the Capture screen sat idle pointed at a static, well-lit,
in-focus scene) and the duplicate/low-quality flagging from §5 correctly
fired on those auto-captured near-identical frames ("Possible duplicate",
"Low quality — consider rescanning").

## 5. Multi-page project management (SPEC 6.3) — task 8

| Item | Status | Evidence |
|---|---|---|
| Immediate per-page persistence | ✅ | `PageRepositoryImpl.addPage`; verified via app-restart test (see below) |
| Crash-safe resume | ✅ | **Verified on-device**: force-killed and relaunched the app mid-session; Library screen showed all previously created projects intact after cold start (real SQLite persistence, not just in-memory state) |
| Thumbnail grid / list, reorder, rotate, duplicate, delete, rescan actions | ✅ | `PageReviewScreen` now has both a reorderable list and a browse-only `GridView` (toggled via a new AppBar action, `_PageGridTile` mirroring `_PageTile`'s popup menu) — grid is browse-only since `ReorderableListView` has no first-party grid equivalent in this Flutter version, so drag-reorder stays List-view-only. **Rescan is now genuinely in-place**: `CapturePageUseCase.replacePage(pageId, capture)` overwrites that page's image content and reruns detect/enhance while preserving its id/sequence/label/filter settings, instead of appending a new page; wired through `CaptureViewModel.replacePageId` + a go_router `extra` param, with the Capture screen auto-popping back to Review after the one replacement capture (a rescan is single-shot, not an open-ended session). Unit-tested (`capture_page_use_case_test.dart`, `page_review_view_model_test.dart`) and exercised end-to-end in `integration_test/rescan_test.dart`. |
| Export button correctly enables once pages load | ✅ | **A real bug was found and fixed** while re-verifying the export flow on-device this session: `bottomNavigationBar`'s `FilledButton.onPressed: _viewModel.pages.isEmpty ? null : ...` was read directly in `_PageReviewScreenState.build()`, but that button sat *outside* the `body`'s `ListenableBuilder` — so it only ever reflected whatever `_viewModel.pages` was at the very first build (almost always still empty/loading), and never updated once pages genuinely loaded. On a fresh cold app start reaching Review pages directly, the Export button was visibly disabled forever even with 10 pages listed above it. Fixed by wrapping the button in its own `ListenableBuilder` listening to `_viewModel`. Added `PageReviewScreen.viewModel` as an injectable constructor param (matching the `CropCorrectionScreen`/`OcrReviewScreen` testability pattern) and a regression test (`test/ui/page_review_screen_test.dart`) using a `StreamController`-backed fake repository to reproduce the exact "button rendered before pages arrive" race — confirmed the test fails without the fix and passes with it. Verified fixed on the Android emulator: Export button now shows enabled (solid blue) once the project's 10 pages load. |
| Duplicate detection (image similarity) | ✅ | `DetectPageAnomaliesUseCase` — perceptual average-hash + Hamming distance. **A real infinite-loop bug was found and fixed** during unit testing: `_hammingDistance` used Dart's arithmetic (sign-extending) `>>` on a value that can be negative (the 64-bit hash can have its top bit set), which never converges to zero. Fixed with a bounded loop and the unsigned `>>>` operator. Confirmed via `flutter test`: full suite (52 tests) green afterward. |
| Missing-page detection (printed page-number gaps) | ✅ | `_findMissingSequenceGaps`; unit-tested |
| Duplicate/OCR-text similarity | ✅ | Now unblocked by task 10's OCR pipeline. `DetectPageAnomaliesUseCase` adds a second, independent duplicate signal: token-Jaccard similarity (≥0.85) over each page's recognized OCR text, only for pages the perceptual image hash didn't already flag — catches a re-scan of the same physical page under different lighting/crop/rotation that pixel hashing misses. Unit-tested with a case specifically constructed so the image hash would miss it but the text signal catches it. |
| 500+ page memory-safe handling | 🟡 | Architecture supports it (thumbnails separate from full-res files, no bulk in-memory loading, per-page background-isolate processing), but not load-tested at that scale |
| Right-to-left books / page order direction | 🟡 | `PageOrderDirection` modeled in `ProjectMetadata`; not yet wired into any UI or export ordering logic |
| Roman numerals / skipped/unnumbered pages | 🟡 | `logicalPageLabel` is a free-form string that supports this, but no UI exists yet to *set* page numbering schemes |

## 6. Book mode (SPEC 5.2, 6.2, 6.3, 9.3) — task 9

✅ **Implemented (classical Dart baseline) and unit/widget-tested.**
🚫 **On-device verification blocked this session** — see the environmental
note below. Real, not a stub: genuine gutter detection, curvature
flattening, and finger-occlusion detection all run and produce different
output for different input, backed by dedicated tests, but this is a
classical CV baseline, not the "learned segmentation/dewarping pipeline"
SPEC 9.3 describes as the target — see documented limitations below.

| Item | Status | Evidence |
|---|---|---|
| `DartBookDewarpProvider` — Sobel column-energy gutter detection, quadratic top/bottom-edge curve fitting for flattening, HSV skin-tone occlusion heuristic | ✅ | `lib/data/services/scanner/adapters/dart_book_dewarp_provider.dart`; 7 unit tests (`test/data/scanner/dart_book_dewarp_provider_test.dart`) covering clear/low-confidence gutter detection, explicit-override splitting, flat-page passthrough, real-curvature flattening, and core-region-vs-margin-only occlusion classification |
| `BookDewarpProvider.splitSpread` extended with an optional `gutterXOverride` for manual correction, full confidence when user-specified | ✅ | `lib/domain/providers/book_dewarp_provider.dart` |
| `ProcessBookSpreadUseCase` — orchestrates split → per-half detect/enhance/dewarp → persist two cross-linked (`spreadSiblingPageId`) pages in correct reading-order sequence per `PageOrderDirection`; `resplit()` for manual correction | ✅ | `lib/domain/use_cases/process_book_spread_use_case.dart`; 7 unit tests (`test/domain/process_book_spread_use_case_test.dart`) |
| Undivided spread photo retention (needed for manual re-split) | ✅ | `ProcessBookSpreadUseCase.spreadOriginalPathFor` — deterministic, order-independent shared storage key derived from both sibling page ids; verified round-trip in its own test |
| Finger/occlusion → `QualityWarning.fingerCovering` + `PageStatus.needsRescan` on high-confidence text loss, warning-only (no rescan) on margin-only occlusion | ✅ | Same use-case tests; never silently removes/inpaints pixels (SPEC 9.3) |
| Capture flow wiring: book-type projects route through the spread pipeline instead of the single-page one, page order direction read from project metadata | ✅ | `CaptureViewModel.captureManually` now returns `List<ScanPage>` (1 for documents, 2 for book spreads) |
| Manual split-correction UI (`SpreadSplitScreen`/`ViewModel`): shows the undivided spread photo with one draggable vertical gutter handle, Cancel/Save | ✅ | `lib/ui/features/page_review/{view_models,views}/spread_split_*.dart`; 3 widget tests (`test/ui/spread_split_screen_test.dart`), built against a *real* `ProcessBookSpreadUseCase` + real classical provider (not fully mocked), so the tests exercise genuine file I/O and pipeline orchestration |
| Entry point: "Re-split spread" in Page Review's popup menu, shown only when `page.spreadSiblingPageId != null` | ✅ | `page_review_screen.dart` |
| DI registration | ✅ | `service_locator.dart` |

**Documented limitations (classical heuristics, not a learned model — same
honesty standard as the other classical fallbacks in this codebase):**
- Gutter detection assumes a roughly centered, visible spine shadow/crease
  (searches only 35%-65% of frame width); an off-center or very worn gutter
  won't be found automatically, but the manual split-correction UI covers
  that case per the SPEC acceptance criterion.
- Curvature flattening fits one quadratic per page edge — corrects the
  common "page bows away from the spine" distortion but not S-curves or
  highly irregular deformation.
- Occlusion detection is an HSV skin-tone heuristic, not a hand/finger
  classifier — can miss gloved hands or trigger on skin-colored page
  backgrounds. It never attempts pixel reconstruction; per SPEC 9.3 it only
  flags for review/rescan.
- No native (ML Kit/Vision-equivalent) adapter exists for this provider;
  only the Dart baseline. `BookDewarpProvider.isSupported()` is honest
  (`true` for the classical baseline, since it always runs — no fake
  "supported" claim for capability a real learned model would add).

**A real bug was found and fixed during unit testing:** the dewarp job
called `img.grayscale(decoded)` to build the Sobel edge map, then reused
`decoded` for the skin-tone occlusion check — but `package:image`'s
`grayscale()`/`sobel()` mutate their input image in place and return the
same reference. `decoded` was silently grayscale by the time occlusion
detection ran on it, so every pixel's saturation was 0 and the skin-tone
heuristic could never fire. Caught by two failing occlusion tests (both
asserted `occlusionDetected: true`, got `false`); root-caused by tracing
actual pixel values through a scratch script before finding the mutating
call. Fixed by cloning (`img.Image.from(decoded)`) before the destructive
grayscale/Sobel chain, leaving the color original intact for occlusion
detection. All 7 provider tests pass afterward.

**✅ On-device verification succeeded** after resolving a genuine emulator
health problem (see below): created a Book-type project, tapped the
shutter once in the Capture screen, and got **"2 pages scanned"** from a
single spread photo — confirming the split pipeline runs correctly on
real hardware. Auto-capture continued to fire against the static test
scene over several minutes, accumulating 10 pages (5 spreads × 2), and
every single one alternated correctly between the physical left half
(bookshelf content, consistently flagged "Low quality" by the sharpness
scorer) and right half (checkerboard content, consistently flagged
"Possible duplicate" by perceptual-hash comparison across repeated
captures of the same static frame) — i.e. the gutter-detection split
found the same correct boundary consistently across many real captures,
not just once by luck. Opened page #1's popup menu, confirmed "Re-split
spread" is present (proving `spreadSiblingPageId` linkage), opened
`SpreadSplitScreen`, confirmed it renders the full undivided spread photo
(proving spread-photo retention actually works, not just in tests) with
the gutter handle positioned right at the real visual boundary between
the bookshelf and TV, dragged the handle, tapped Save, and confirmed it
navigated back to Review pages with no exceptions in logcat — proving
`resplit()` genuinely works on-device too.

**Diagnosing a false alarm along the way:** the first three on-device
attempts this session hit system-level ANRs ("System UI isn't
responding" / "Process system isn't responding" / "bookscanner isn't
responding") before the app finished launching, even surviving a full
`adb reboot` of the emulator OS. This looked like it could be a real
performance problem in the new, meaningfully heavier book-mode pipeline
(per spread: 1 split + 2×(detect+enhance+dewarp), roughly 4x a normal
single-page capture). The actual root cause, found by reading `logcat`
line-by-line rather than guessing: **Google Play Services
(`com.google.android.gms`) runs a one-time background dexopt/optimization
pass over a dozen+ dynamite modules (MlkitOcrCommon, VisionOcr,
TfliteDynamite, MeasurementDynamite, etc.) immediately after a fresh
emulator's first boot**, which pegged system CPU/Binder bandwidth badly
enough to cause multi-second Binder call delays (`Binder transaction to
android.content.pm.IPackageManager ... took 6633ms`) system-wide —
enough to ANR *SystemUI and the package manager themselves*, not just our
app. This is a well-known, transient, one-time cost on freshly-booted
emulators and had nothing to do with the book-mode code. Confirmed
resolved by waiting ~2.5 minutes for the `artd: GetBestInfo` log spam to
stop, after which the app launched cleanly and stayed responsive through
the entire verification above. Also needed, earlier in the same
troubleshooting arc: the original long-running emulator instance (up
continuously across this whole multi-hour session) had degraded to the
point that even a full OS reboot didn't clear its instability, and had to
be replaced with a genuinely fresh emulator process (`kill` the old qemu
process, launch a new one) — worth remembering for future sessions: an
OS-level `adb reboot` is not always enough to recover a long-running
emulator; a full process restart may be needed, and a fresh boot's first
1-3 minutes of GMS dexopt should be expected and waited out rather than
treated as a hang.

## 7. OCR pipeline + searchable PDF + review (SPEC 6.4, 9.4) — task 10

✅ **Implemented and verified on-device (Android emulator, real ML Kit
inference).** Closes the SPEC 9.4 requirement for on-device text
recognition plus cross-platform layout reconstruction.

| Item | Status | Evidence |
|---|---|---|
| `OcrChannelContract` (Dart/Kotlin/Swift) — versioned channel mirroring the capture-plugin pattern | ✅ | `lib/data/services/ocr/ocr_channel_contract.dart`, `android/.../ocr/OcrContract.kt`, `ios/Runner/Ocr/OcrContract.swift` |
| `OcrPlatformChannel` + `NativeOcrProvider` (Dart) | ✅ | `lib/data/services/ocr/ocr_platform_channel.dart`, `lib/data/services/ocr/adapters/native_ocr_provider.dart` |
| Native Android adapter: ML Kit Text Recognition v2 (Latin, on-device, no network) | ✅ | `android/app/src/main/kotlin/.../ocr/OcrPlugin.kt`; dependency `com.google.mlkit:text-recognition:16.0.1` added to `build.gradle.kts` |
| Native iOS adapter: Vision `VNRecognizeTextRequest` | ✅ (compiles, builds for Simulator) / 🚫 (real inference unverified — no physical device, see §3's blocker) | `ios/Runner/Ocr/OcrPlugin.swift`; registered in `AppDelegate.swift`; added to `project.pbxproj` via the `xcodeproj` gem, same as the capture plugin |
| **Documented cross-platform confidence-signal gap** | ✅ (honest, not faked) | ML Kit's on-device Latin recognizer does not expose a real per-word/line confidence score in its public API, so `OcrPlugin.kt` reports a constant `1.0` ("no signal") for every word/line — SPEC 6.4's low-confidence flagging will not surface anything on Android until ML Kit exposes this. iOS Vision's `VNRecognizedText.confidence` *is* a genuine per-line score, so iOS gets real confidence once verified on hardware. Documented in both plugin files' doc comments, not silently fabricated. |
| `AnalyzeOcrLayoutUseCase` (cross-platform layout reconstruction: reading order incl. simple 2-column detection, paragraph-line merging, heading/list-item/page-number/header/footer/quotation classification) | ✅ | `lib/domain/use_cases/analyze_ocr_layout_use_case.dart`; 8 unit tests in `test/domain/analyze_ocr_layout_use_case_test.dart`, all passing. Documented limitations: multi-column support is a single left/right split per contiguous run (no 3+ column support); headings are single-level; table/table-cell detection is not implemented (classified as paragraphs) |
| `RunOcrUseCase` (orchestrates recognize → analyze → persist, records `PipelineStage.ocr`, skips re-recognition unless `force: true`) | ✅ | `lib/domain/use_cases/run_ocr_use_case.dart`; 5 unit tests in `test/domain/run_ocr_use_case_test.dart` |
| `OcrReviewScreen` + `OcrReviewViewModel` (empty state → Recognize text → block list with low-confidence/corrected badges → tap-to-correct dialog → re-run) | ✅ | `lib/ui/features/ocr_review/`; 4 widget tests in `test/ui/ocr_review_screen_test.dart` |
| Entry point from Page Review popup menu ("Recognize text") | ✅ | `page_review_screen.dart` |
| `FakeOcrProvider` + contract test | ✅ | `lib/data/services/ocr/adapters/fake_ocr_provider.dart`; `test/data/ocr/ocr_provider_contract_test.dart` (3 tests) |
| PDF invisible-text-overlay integration | ✅ (mechanism, pre-existing) / ✅ (now receives real data) | `_invisibleTextOverlay` in `dart_document_export_provider.dart` already consumed `page.ocrBlocks`; now that `RunOcrUseCase` persists real blocks, searchable-PDF export has genuine text to embed (not independently re-verified via a fresh PDF export in this session, but the data path is now populated) |

**On-device verification (Android emulator, real ML Kit model, two passes):**
1. Ran "Recognize text" against a synthetic scene photo with no actual text
   in it. Real ML Kit models loaded (`Loading mlkit-google-ocr-models/...`
   in logcat) and genuinely recognized zero lines — this is correct
   behavior, not a bug. **Found and fixed a real bug this exposed:**
   `OcrReviewViewModel.hasRun` was originally derived from
   `blocks.isNotEmpty`, which cannot distinguish "never run" from "ran,
   found nothing" — a textless page would show "OCR has not been run yet"
   forever even after a successful run. Fixed by tracking `hasRun` from the
   page's `PipelineStage.ocr` stage record (written by `RunOcrUseCase`
   regardless of block count) instead of block count, and added a distinct
   "No text was found on this page" state. Regression-tested in
   `ocr_review_screen_test.dart`.
2. To verify the actual recognition/parsing path (not just the empty-result
   path, which never exercises the Kotlin bounding-box/word-extraction
   code), generated a real JPEG containing two lines of rendered text
   (`Hello BookScanner` in 48pt, a smaller line in 24pt) using the `image`
   package's bundled bitmap font, swapped it in for an existing page's
   processed-image file on-device via `adb` + `run-as`, and forced a
   re-run. **Real ML Kit inference correctly recognized both lines**, and
   `AnalyzeOcrLayoutUseCase` correctly classified the larger line as a
   heading (rendered bold in the UI) and the smaller line as a plain
   paragraph — proving the full channel round-trip, bounding-box
   normalization, and layout heuristics work correctly on genuine
   recognized content, not just synthetic unit-test fixtures.

## 8. PDF export/editing (SPEC 6.5) — task 11

| Item | Status | Evidence |
|---|---|---|
| Multi-page PDF, page size/orientation/margins/quality options | ✅ | `DartDocumentExportProvider.exportPdf`; unit-tested (`dart_document_export_provider_test.dart`) — verifies `%PDF-`/`%%EOF` markers and page-object count |
| Image-only export | ✅ | same |
| Searchable export (invisible text layer) | ✅ **verified end-to-end on-device with real OCR data** | Ran a Searchable PDF export against the project containing the real-OCR test page from §7. Pulled the resulting PDF off the Android emulator via `run-as`, decompressed its FlateDecode content streams with a throwaway Python/zlib script (since no PDF text-extraction tool was available in this environment), and confirmed the literal `Tj`/`TJ` show-text operators contain the exact recognized words — `[(Hello)]TJ ... [(BookScanner)]TJ` and `[(This)]TJ [(is)]TJ [(a)]TJ [(real)]TJ [(OCR)]TJ [(test)]TJ [(line.)]TJ` — each positioned over its corresponding word in the page image (`/I17 Do`). This is genuine proof the invisible-text overlay carries real, per-word OCR output into the exported file, not just a structural/mechanism check. |
| Watermark | ✅ | `_watermark` in the same file |
| Password protection / encryption | 🚫 | **Deliberately not implemented, not faked.** Explored the `pdf` package's low-level `PdfEncryption` hook (Standard Security Handler, RC4) but scoped it out of this session to prioritize core scanning; `exportPdf` throws an explicit `ProviderException(unsupportedDevice, "PDF password protection is not yet implemented")` rather than silently shipping an unprotected file when a password was requested. Verified via test: `dart_document_export_provider_test.dart` asserts the exception is thrown. |
| Merge/split/insert/replace/extract/duplicate/rotate/reorder/delete pages | 🟡 (implemented, unit/widget-tested; not yet verified on-device) | See §8a below |
| Compress with size estimate/preview | ⛔ | Not started (out of scope for this slice — deferred by explicit choice, along with annotations below, to keep the page-operations slice reviewable on its own) |
| Annotations, highlights, signatures, redaction | ⛔ | Not started (deferred, see above) |
| Share / system file picker / print | 🟡 | `share_plus` wired in `ExportScreen` for the completed-export share action; system file picker and print not wired |

### 8a. Multi-source page-composition ("editing") — task 11, first slice

Scoping note: BookScanner's own scanned pages already have full rotate/
reorder/duplicate/delete via Page Review, persisted per-page and wired into
export (`ExportProjectUseCase`) — rebuilding that would be redundant. The
actual gap this slice closes is **multi-source composition**: merging
another project's pages, an imported PDF's pages, or a plain image into one
working document, then reordering/rotating/duplicating/deleting/inserting/
replacing/splitting/extracting *within that combined list* before exporting.

| Item | Status | Evidence |
|---|---|---|
| `LoadProjectPageInputsUseCase` (shared page-loading loop, extracted out of `ExportProjectUseCase` without changing its behavior) | ✅ | `lib/domain/use_cases/load_project_page_inputs_use_case.dart`; regression-guarded by `test/domain/export_project_use_case_test.dart` (default behavior unchanged; custom loader honored) |
| `PageSource` (project / external PDF / image) + `LoadPageSourceUseCase` | ✅ | `lib/domain/models/page_source.dart`, `lib/domain/use_cases/load_page_source_use_case.dart`; 4 unit tests in `test/domain/load_page_source_use_case_test.dart` |
| `PdfRasterizerProvider` — reads an existing PDF's pages as bitmaps via `package:printing`'s native PDFium/PDFKit renderer | ✅ (fake-verified) / 🟡 (real adapter unverified — needs a device, see below) | `lib/domain/providers/pdf_rasterizer_provider.dart`; real `PrintingPdfRasterizerProvider` + `FakePdfRasterizerProvider`, contract test in `test/data/export/pdf_rasterizer_provider_contract_test.dart`. **Documented, deliberate tradeoff**: neither `pdf` nor `printing` can parse an existing PDF's vector/text object graph (no concrete `PdfDocumentParserBase` ships in either package) — only rasterize its pages. Imported PDF pages are therefore flattened to images and are not searchable unless OCR is explicitly rerun on them (out of scope here); this is surfaced in the compose UI via a "N of M pages have no recognized text yet" warning rather than silently claimed as searchable. |
| `WorkingSessionPathAllocator` (ephemeral scratch storage for a composition session, separate from `PagePathAllocator` so its 6 existing implementers didn't need to change) | ✅ | `lib/domain/repositories/working_session_path_allocator.dart`, `lib/data/services/local/app_working_session_paths.dart` (nests under `AppPaths.tmpDir`); 3 unit tests in `test/data/local/app_working_session_paths_test.dart` |
| `ExportPageInputsUseCase` — exports an explicit page list (`exportPdf`) or one job+file per group (`splitPdf`), reusing the existing `DocumentExportProvider`/`ExportJobRepository` plumbing without touching `ExportProjectUseCase` | ✅ | `lib/domain/use_cases/export_page_inputs_use_case.dart`; 3 unit tests in `test/domain/export_page_inputs_use_case_test.dart` (completed job with a real PDF, failure path, 2-group split producing 2 valid files) |
| `PageOperationsViewModel` — ephemeral, in-memory working list (not persisted through `PageRepository`, matching `CropCorrectionViewModel`/`SpreadSplitViewModel`'s transient-state pattern); reorder/rotate/duplicate/delete/insertBefore/replace/mergeAppend/toggleSplitAfter/toggleSelectedForExtract/exportWhole/extractSelected/exportSplit; split markers and extract-selection are keyed by page id (not index) so they survive a reorder | ✅ | `lib/ui/features/page_operations/view_models/page_operations_view_model.dart`; 14 unit tests in `test/ui/page_operations_view_model_test.dart` covering list mechanics, split-marker survival across reorder, merge/insert/replace against fakes, and end-to-end export/extract/split against the real `DartDocumentExportProvider` (including a page-count assertion proving `extractSelected` embeds only the selected subset) |
| `PageOperationsScreen` — `ReorderableListView` + per-page popup menu (mirrors `PageReviewScreen`'s exact pattern), extract-select mode with checkboxes, split-marker dividers, source-picker sheet (project / PDF / image), and export/extract/split result views (reusing extracted `ExportProgressView`/`ExportCompletedView`/`ExportFailedView` for the single-output case, a small screen-local multi-file results view for split) | ✅ | `lib/ui/features/page_operations/views/page_operations_screen.dart`, `source_picker_sheet.dart`; 8 widget tests in `test/ui/page_operations_screen_test.dart` |
| Entry point + route | ✅ | New `exportComposeButton` action on `ExportScreen`'s AppBar → `AppRoutes.pageOperations` (`/projects/:projectId/compose`); `ExportScreen`'s existing `_ProgressView`/`_CompletedView`/`_FailedView` were extracted into public `export_job_status_views.dart` so both screens share them, with unchanged `ValueKey`s (no existing test needed to change) |
| `flutter analyze` / full test suite | ✅ | Clean; 151/151 tests passing (108 pre-existing + 43 new for this slice) |
| **On-device verification** | 🚫 **Not attempted this session.** | Host had only ~1GB free RAM at the time (`vm_stat`) — well above the ~60-76MB crisis level that caused severe ANRs/GC-churn documented in §2/§3/§4a of this doc, but still tight enough that booting an emulator plus a Gradle daemon risked repeating that multi-hour troubleshooting pattern for uncertain benefit given the feature is already exercised end-to-end (real file I/O, real PDF assembly, real `DartDocumentExportProvider`) by 22 passing unit/widget tests. Needs a real device/emulator pass before this row can move to ✅: merge in a second project and an external PDF, insert/replace a page, verify a split export produces two openable PDFs, and specifically confirm `Printing.raster`'s page-emission order matches the requested `pageIndices` order (flagged as an assumption in `printing_pdf_rasterizer_provider.dart`'s doc comment, verifiable only against the real PDFium/PDFKit renderer). |

**A real bug was found and fixed while writing `ExportScreen` widget tests:**
`ExportProjectUseCase.export()` persisted a `failed` `ExportJob` to the
repository on error, then `rethrow`n the exception. `ExportViewModel.
startExport()` awaited `export()` inside a `try` block and only assigned
`_job = job;` on the success path — so when an export failed, the
exception skipped that assignment entirely and `ExportViewModel.job`
stayed `null`. `ExportScreen`'s build method only shows `_FailedView`
(with the retry button) when `job != null && job.status == failed`, so
**the failed/retry UI was completely unreachable** — a real export failure
would silently fall back to re-showing the format picker with no
indication anything went wrong. Fixed by having `export()` return the
failed job normally instead of rethrowing (a failed export is an expected
business outcome the UI must render, not exceptional control flow — the
same pattern already used by `SpreadSplitResult`/`DewarpResult` elsewhere
in this codebase). Caught by `test/ui/export_view_model_test.dart`
asserting `viewModel.job?.status == ExportJobStatus.failed` after a
real (not mocked) export failure — this failed against the
pre-fix code with `job` still `null`.

**Testing-infrastructure lesson from the same investigation:** an earlier
version of this test drove the real export through a pumped
`ExportScreen` widget using `tester.runAsync(() => viewModel.
startExport(...))`, which hung for the full default test timeout (~10
minutes) twice. Root cause: `ExportViewModel.startExport` creates a
`StreamSubscription` via `_exportJobRepository.watchJob(job.id).
listen(...)` that never completes/cancels; `tester.runAsync`'s zone-idle
detection waits for all async work started inside it to quiesce, and a
live, uncancelled `StreamSubscription` on a still-open `StreamController`
counts as outstanding work forever. Fixed at the test level (not a
product bug) by testing `ExportViewModel`'s async behavior with plain
`test()` calls instead of `testWidgets()` — a plain `test()` body runs on
the real event loop with no fake-clock zone, so this class of hang cannot
occur; `testWidgets()` is reserved for verifying the `Scaffold` actually
renders the right child, which doesn't require driving a real export
through it. See the doc comment atop `test/ui/export_view_model_test.dart`.

**A second, related `flutter_test` infrastructure lesson surfaced while
writing `test/ui/capture_screen_test.dart`:** an early version reused the
existing `FakeCaptureProvider` (built for contract/integration tests),
whose `openSession()` starts a real `Timer.periodic(100ms)` that keeps
emitting synthetic analysis frames. Because `CaptureViewModel.initialize()`
opens that session from `initState()`, the timer gets created inside
`flutter_test`'s per-test `FakeAsync` zone. Calling `await
viewModel.closeSession()` directly in the test body (to cancel it and
avoid `flutter_test`'s end-of-test "no pending timers" check) hung for the
full default test timeout instead of resolving — killed manually after
8+ minutes real time, confirmed hung (not just slow) via `ps`. The
mechanism differs from the `ExportViewModel`/`runAsync` case above (no
`runAsync` was even involved here), and wasn't worth root-causing further
given `fake_async`'s zone-reentrancy semantics are subtle; the practical
fix was to stop fighting it. `CaptureScreen`'s widget tests don't need a
live analysis stream at all (auto-capture behavior isn't in scope for
that test file), so the fake was replaced with a purpose-built
`_TestCaptureProvider` whose `analysisStream()` returns `const
Stream.empty()` and whose `openSession()`/`closeSession()` never touch a
`Timer` — with nothing live to leak or cancel, the whole class of problem
disappears. General takeaway: a `CaptureProvider`/similar fake used in a
`testWidgets()` test should not run a periodic timer unless that test
specifically exercises the behavior driven by it.

## 9. Markdown export (SPEC 6.6) — task 12

| Item | Status | Evidence |
|---|---|---|
| UTF-8 Markdown, headings/paragraphs/lists/quotes | ✅ | `MarkdownWriter`; unit-tested including a UTF-8 round-trip assertion (`café` etc.) |
| Page-boundary comments | ✅ | tested |
| YAML front matter | ✅ | tested |
| `assets/` directory with relative image links (fallback when no OCR) | ✅ | tested |
| Tables (Markdown / HTML fallback) | ⛔ | Not implemented — needs the OCR layout stage (task 10) to know table structure first |
| ZIP packaging | ✅ | tested |

## 10. Word (DOCX) export (SPEC 6.7) — task 12

| Item | Status | Evidence |
|---|---|---|
| Hand-rolled standards-compliant OOXML package | ✅ | `DocxWriter`; unit-tested: unzips output, parses `word/document.xml` and `docProps/core.xml` as well-formed XML, asserts heading/list/paragraph structure and Unicode text |
| Reflowable / preserve-page-breaks / facsimile modes | ✅ | all three unit-tested |
| Image embedding (facsimile mode) | ✅ | tested — verifies `word/media/imageN.jpg` and relationship wiring |
| Tables, footnotes, headers/footers | ⛔ | needs OCR layout stage |
| Manual inspection in real Microsoft Word | 🚫 | No Word installation available in this environment; structural validity was verified programmatically (well-formed OOXML, correct relationships/content-types) but not by opening in actual Word/LibreOffice, which SPEC 13 also requires before release |

## 11. Organization, security, privacy, accessibility (SPEC 6.8–6.11) — task 13

| Item | Status | Evidence |
|---|---|---|
| Library: recent items, search, favorites | ✅ | `LibraryScreen`/`LibraryViewModel`; widget-tested (empty/loaded/search-filter states) |
| Library rows with a per-project context menu (Delete; Recognize text) | ✅ | **User-requested, session 4.** Replaced the `GridView`-of-`ProjectGridTile`-cards layout with `ListView.builder` of `ProjectListRow` (key `libraryList`, was `libraryGrid`) — each row shows the thumbnail, title, and a `{count} pages` subtitle, with a trailing favorite toggle plus a `PopupMenuButton` (key `projectRowMenu`) offering "Delete" (wired to the existing `LibraryViewModel.moveToTrash`, already implemented, just never exposed before) and "Recognize text" (present but `enabled: false` -- whole-project text extraction, distinct from the existing per-page OCR action, is a real future feature, not hidden but explicitly not yet built, per the user's own "to be impl later"). `project_grid_tile.dart` deleted as fully superseded. Widget-tested: menu shows both items with Recognize text disabled; tapping Delete removes the row and the project falls out of the default (non-trashed) query. |
| Folders/tags | 🟡 | Repository + DB layer complete (`FolderRepositoryImpl`); no UI to create/assign folders or tags yet |
| Trash/recovery | 🟡 | `moveToTrash`/`restoreFromTrash` implemented and unit-tested, and `moveToTrash` now has a real UI trigger (the library row's Delete menu item above); still no dedicated trash/recovery screen to undo it from |
| Rename (single) | ✅ | wired in `LibraryViewModel`; still no UI affordance in the library row itself (the new "Name this scan" dialog on Capture's Done — see §4 — covers naming a project right after it's created, which was the more pressing gap) |
| Batch rename | ⛔ | Not started |
| Sort/filter, thumbnail/list views | 🟡 | List view now (was grid — see the library-rows row above); sort/filter options not exposed in UI |
| Cloud backup/sync | ⛔ | Out of MVP scope per SPEC 8; no provider selected |
| App lock (biometric/PIN) | ✅ | `SettingsScreen`/`SettingsViewModel` using `local_auth`; not yet enforced at app launch (settings toggle exists and persists, but nothing currently gates entry to the app behind it) |
| Encrypted storage | 🟡 | Local DB and files use standard app-private storage (already sandboxed by the OS); `flutter_secure_storage` dependency is added but not yet used for anything — no secrets currently need it since there's no password/API-key state yet |
| Cloud-processing consent gating | 🟡 | `AppSettings.cloudProcessingConsentGiven` modeled and displayed; no cloud provider exists yet to gate, so the consent flow has nothing to gate in front of |
| EXIF/location stripping on export | 🟡 | `AppSettings.stripLocationMetadata` setting exists; **not actually enforced yet** — the enhancement pipeline re-encodes JPEGs via `package:image`, which does not carry forward EXIF GPS tags by default (a side effect, not a verified deliberate strip), so this needs an explicit test before being marked done |
| Copyright/responsible-use onboarding notice | ⛔ | Not built |
| Accessibility (screen reader labels, dynamic text, contrast, reduced motion) | 🟡 | Standard Material widgets inherit reasonable defaults; no explicit `Semantics` audit performed; capture screen's shutter button has an explicit `Semantics(button: true, label: ...)` as a start |
| RTL layout | ⛔ | Not tested — no RTL locale configured or exercised |

## 12. Testing (SPEC 13) — task 14

| Type | Status | Evidence |
|---|---|---|
| Unit tests: domain models | ✅ | `test/domain/scan_page_test.dart`, `ocr_block_test.dart` |
| Unit tests: use cases | ✅ | `test/domain/detect_page_anomalies_use_case_test.dart` (found + fixed the Hamming-distance infinite loop) |
| Unit tests: repositories (real SQLite) | ✅ | `test/data/*_impl_test.dart`, 6 files, all against `sqflite_common_ffi` |
| Unit tests: export writers | ✅ | `test/data/export/*.dart` — PDF structural checks, Markdown UTF-8/front-matter/zip, DOCX OOXML well-formedness |
| Contract tests: provider adapters | ✅ (fake only) | `capture_provider_contract_test.dart`, `ocr_provider_contract_test.dart`; needs to be re-pointed at the native Android/iOS adapters once they can run in an instrumented environment |
| Widget tests | ✅ | `LibraryScreen`, `CropCorrectionScreen`, `OcrReviewScreen`, `PageReviewScreen` (Export-button-enables-after-async-load regression test), `SpreadSplitScreen`, `ExportScreen`, `SettingsScreen`, and `CaptureScreen` (permission-gating states plus a real manual-capture-increments-page-count flow) all covered (plus `ExportViewModel`'s async export success/failure behavior via plain `test()`s — see §8). Every top-level screen now has at least one widget test. |
| Golden/corpus image tests | ✅ | See §12a below |
| Integration tests (`integration_test/`) | 🟡 | `capture_flow_test.dart` and `book_scan_session_test.dart` **verified passing on-device** (Android emulator / iOS Simulator, see §3/§9). Four more files added this session covering the rest of SPEC 13's list — **written and reviewed, but not yet run**, since no emulator boot was safe this session (host memory oscillated between ~80MB-1GB free across checks; see §8a's note on the same constraint): `interrupted_session_recovery_test.dart` (already existed, not new this session — a captured page survives a simulated cold app restart before "Done" is tapped, proving SPEC 9.2's "persist immediately" claim), `provider_fallback_test.dart` (**found and fixed a real bug**: an always-throwing `PageDetectionProvider` used to abort the whole capture and lose the already-captured original image — see task 7's row above — now falls back to `Quad.fullFrame` and the capture completes normally), `rescan_test.dart` (the new in-place-replace rescan flow end to end: same page id, same page count, new image content), `pdf_docx_export_test.dart` (PDF and DOCX export each produce a real file with the correct format signature — Markdown was already covered by `book_scan_session_test.dart`). **Not covered, and not a testing gap**: "localization switching" — only `app_en.arb` exists (`AppLocalizations.supportedLocales == [Locale('en')]`); there is no second locale to switch to yet, so this SPEC 13 item is an open product/content gap (someone needs to author a real translation), not something a test can meaningfully exercise by faking a second locale. |
| 300-page memory/performance test | ⛔ | Not started |
| On-device manual verification | ✅ (Android + iOS) | See §2, §3, §4a, §7 |
| Full suite passing | ✅ | `flutter test` → 195/195 passing (172 as of the golden/corpus-test milestone + 23 added for tasks 7/8/14's filter UI, grid view, in-place rescan, OCR-text-similarity duplicates, and the detection-fallback fix); `flutter analyze` clean. `capture_flow_test.dart`/`book_scan_session_test.dart` verified passing on-device as of session 2; the 4 newer `integration_test/` files are written/reviewed but not yet run on a device this session (see §12's integration-tests row). |

### 12a. Golden/corpus image tests — task 14

Scoping correction made during this session: "golden/corpus image tests" does
**not** mean UI screenshot testing — rereading SPEC.md (lines 317, 385, 387)
clarified this is **pipeline golden-image regression testing**: run the
classical image-processing pipeline against a **consented test corpus**
covering flat pages, curved books, glossy paper, shadows, fingers, skew, low
light, multi-column layouts, tables, illustrations, and RTL text, then assert
documented behavior. Per explicit decision this session, the corpus is
**synthetic** (built with `package:image`, same technique every other test
file in this codebase already uses — no real scanned photos available/
consented in this environment) and assertions are **behavioral**, not
pixel-diff goldens, so the suite stays robust to intentional algorithm
improvements rather than breaking on every deliberate tweak.

| Item | Status | Evidence |
|---|---|---|
| `test/pipeline_corpus/corpus_images.dart` — the named corpus itself: one documented builder per SPEC category (11 total) | ✅ | Image-based builders (`flatPage`, `curvedBookSpread`/`curvedBookPage`, `glossyPage`, `shadowedPage`, `fingerOcclusionCore`/`Margin`, `skewedPage`, `lowLightPage`) plus OCR-block-based builders for the four layout-only categories (`multiColumnLayoutRawLines`, `tableLayoutRawLines`, `illustrationRawLines`, `rtlTextLayoutRawLines`) |
| `test/pipeline_corpus/pipeline_corpus_test.dart` | ✅ | 12 tests (one per category, 2 for fingers' core-vs-margin split), each running the real relevant pipeline stage (`DartPageDetectionProvider`, `DartImageEnhancementProvider`, `DartBookDewarpProvider`, `AnalyzeOcrLayoutUseCase`) against its corpus fixture |
| Two previously-untested providers filled as a byproduct | ✅ | `test/data/scanner/dart_page_detection_provider_test.dart` (3 tests) and `test/data/scanner/dart_image_enhancement_provider_test.dart` (6 tests) had no dedicated coverage before this session; the corpus work surfaced that gap and filled it with real assertions, not just corpus smoke-tests |
| **Honestly-documented gaps, made into executable regression checks rather than left as prose claims** | ✅ | (1) ~~Page detection is axis-aligned only~~ **closed session 5** — a 12°-rotated synthetic page now returns a tight rotated quad that enhancement warps to a background-free rectangle (`pipeline_corpus_test.dart` skew case). (2) Quality scoring is a pure Laplacian-variance (sharpness) proxy with **no exposure/luminance term** — darkening a sharp image barely changes its score, while blurring it (regardless of brightness) collapses the score; this is the concrete mechanism behind "low light" scoring low, which is worth knowing since it's really scoring blur, not darkness. (3) No dedicated glare/reflection compensation exists for glossy paper — verified this doesn't crash or spuriously zero the whole-page score, not that glare is handled well. (4) `AnalyzeOcrLayoutUseCase` never assigns `BlockType.table`/`tableCell` to anything (confirmed by reading the source: no table-detection logic exists at all) — a table-like grid of cells is asserted to *not* produce table blocks. (5) The same use case has zero script-direction awareness — an RTL fixture where the correct first-read column is the rightmost one is asserted to come out **second**, proving reading order is purely geometric (left-centerX bucket first), matching §5's note that page-order-direction is modeled in metadata only. |
| Scope not covered | — | Real photographic corpus (would need actual consented scans, not available in this environment); golden **pixel** comparisons (deliberately not used, see above); native ML Kit/Vision OCR corpus testing (would need a device/simulator, tracked separately in §7) |

**Two lessons from getting `book_scan_session_test.dart` running, kept
here since they'll recur for any future `integration_test/` work:**

1. **Long-running-emulator degradation, again (see §2/§3's earlier notes on
   this) — but this time confirmed NOT GMS dexopt.** The first attempt at
   this test hung for 8+ minutes with the fake capture/OCR adapters wired
   in correctly, which looked like it could be a real bug. Checked
   `adb shell uptime` first this time instead of assuming: load average
   30-43 on a VM that should sit near 0-1, uptime 6h38m. `logcat` showed
   zero `artd`/`GetBestInfo` lines (ruling out the dexopt explanation from
   earlier sessions) — this was plain resource exhaustion from a
   long-lived instance. Fix was the same as before: kill the qemu process
   and launch fresh (`emulator -avd Medium_Phone_API_36.1 -no-snapshot`).
   The identical test then ran in ~1 minute.
2. **`flutter test integration_test/...` re-installs the app from scratch
   on every run, which resets Android runtime permission grants.**
   Pre-granting camera permission with `adb shell pm grant` before
   starting the test command doesn't survive the tool's own
   uninstall-then-install cycle, so the test hit the "permission not
   granted" branch even though it had been granted moments earlier.
   Worked around by racing the grant against the install in a background
   shell loop (poll `adb shell pm list packages` until the package
   reappears, then `pm grant` immediately) started just before invoking
   `flutter test`; the install takes long enough (Gradle build + push)
   that the grant reliably lands before the test's first permission
   check. This is a test-environment workaround, not a product change —
   a real user grants permission once and it persists normally.

---

## Known blockers requiring user action

1. **No physical iOS device.** (Partially resolved for Android as of
   session 4 — a real device is now connected and in active use; this
   already found two real bugs an emulator never could, see §2 and §4.)
   Camera-hardware-dependent iOS behavior (real focus hunting, real
   lighting, real hand-held motion, flash/torch) cannot be verified at all
   without a physical iPhone — the Simulator has no camera. A physical iOS
   device is needed before iOS can be considered release-verified.
2. **No Apple Developer signing identity.** Needed before an iOS build can
   run on a physical device or be distributed via TestFlight.
3. **No Microsoft Word/LibreOffice installation in this environment.** DOCX
   output has been verified structurally (valid OOXML, correct
   relationships) but not by opening in the actual target application SPEC
   13 asks for.
4. **Product decisions from SPEC §14 remain open** (OCR languages beyond
   English, on-device-vs-hybrid-cloud OCR, business model, cloud backup
   timing/provider, max pages/project, DOCX complex-table/equation support,
   min OS versions). Implementation so far has defaulted to
   on-device-only, English, no cap beyond what SQLite/filesystem allow, and
   simple DOCX structures — these should be confirmed or overridden.

## Immediate next steps (in priority order)

1. Continue expanding `integration_test/` coverage per SPEC 13's full list.
   `book_scan_session_test.dart` now covers multi-page book session, OCR
   correction, and Markdown export (see §12) — still open: interrupted-
   session recovery, page reorder/rescan, PDF/DOCX export, provider
   fallback, localization switching.
2. Real per-platform camera *and* OCR verification on physical hardware
   remains blocked (§3, §7) — the iOS Vision adapter has never run on
   real hardware (Simulator has no camera and this session had no way to
   exercise it independent of the capture flow); flag again once a device
   is available.
3. Emulator-health lessons from this session, for future on-device work:
   (a) a long-running emulator instance can degrade badly enough that
   even an OS-level `adb reboot` won't fix it — a full process restart
   (`kill` the qemu process, launch fresh) may be needed; (b) a
   freshly-booted emulator spends its first 1-3 minutes with Google Play
   Services doing one-time background dexopt, which can ANR *SystemUI
   and the package manager themselves* — wait it out before assuming a
   hang; (c) still separately worth checking `vm_stat` for host memory
   pressure (§2, §3, §4a's GC-churn/~60MB-free-RAM pattern) as a third,
   independent failure mode from the above two.
4. Markdown/DOCX export against a page with real OCR data was not
   independently re-verified this session (only Searchable PDF was) — do
   that next since it's a small follow-up now that the export pipeline is
   confirmed working with real blocks.
5. `BookDewarpProvider` still has no learned ML adapter — the Dart
   classical baseline now persists dewarped JPEGs under `processed/` and
   regenerates thumbnails from that final image. OpenCV 4.11 is wired for
   Android page detection/enhance; iOS OpenCV linking is the remaining
   native step before physical iOS validation.
