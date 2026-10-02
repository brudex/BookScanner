# AGENTS.md

Instructions for any AI coding agent (Claude, Codex, Cursor, etc.) working in
this repository. Read this before making changes.

## Orientation — read these first, in order

1. **`SPEC.md`** → points to `SPEC-V1.md` (build this first) and `SPEC-V2.md`
   (only after V1, unless a delivery plan explicitly says otherwise). These
   are the authoritative requirements. If code and spec disagree, the spec
   wins unless the user says otherwise.
2. **`IMPLEMENTATION_STATUS.md`** — the living traceability doc mapping every
   spec requirement to its status, source files, tests, and evidence. This is
   the single source of truth for "what's actually done." Update it as part
   of any task that changes implementation status — see rules below.
3. This file, for how to work in the codebase day to day.

There is no `CLAUDE.md` — this file serves that role for all agents.

## Non-negotiable rule: honest status reporting

`IMPLEMENTATION_STATUS.md` uses this legend:

- ✅ Implemented **and verified** (test passed and/or observed working)
- 🟡 Implemented, not yet independently verified
- ⛔ Not started
- 🚫 Blocked by an external dependency (physical device, signing identity,
  missing tooling, etc.) — document the specific blocker

**Never mark something ✅ without having actually run it.** Writing code that
looks correct is not evidence. If you wrote a test, run it and see it pass
before claiming the row is done. If something can only be verified on a
physical device/simulator you don't have, mark it 🟡 or 🚫 and say exactly
why. This project has caught and fixed real bugs (ANRs, silently-dropped
pages on provider failure, auto-capture runaway loops) specifically because
status was never inflated — keep it that way. Same standard applies to
whatever you tell the user in chat, not just the doc.

When you finish a slice of work, update `IMPLEMENTATION_STATUS.md`'s
relevant table row(s), the "Last updated" line at the top (with a short
summary of what changed), and leave clearly-worded notes for anything
deferred rather than dropping it silently.

## Architecture (SPEC 9.1.1) — do not violate these boundaries

```
lib/
  domain/        # Pure Dart. Models, repository interfaces, provider
                  # interfaces, use cases. No Flutter, no platform SDKs.
    models/
    repositories/  # abstract interfaces only
    providers/     # abstract interfaces only (Capture, PageDetection,
                    # ImageEnhancement, BookDewarp, Ocr, DocumentExport,
                    # PdfRasterizer, ConversionApi)
    use_cases/
  data/          # Concrete implementations of domain interfaces.
    repositories/  # *_impl.dart
    services/
      scanner/adapters/   # capture, OpenCV + Dart detection/enhance, dewarp
      ocr/adapters/       # real + fake OcrProvider
      export/             # PDF, DOCX, Markdown, EPUB writers + rasterizer adapters
      local/              # sqflite DatabaseService, AppPaths
      remote/             # BookScannerApiClient (ConversionApi)
  ui/
    core/di/service_locator.dart   # single composition root (get_it)
    core/app_lock_controller.dart
    features/
      capture/
      library/          # library, folders, favorites, trash, search, book setup
      page_review/      # review, crop, filter, spread split, post-capture edit
      page_operations/
      ocr_review/
      export/
      settings/         # settings + unlock
      onboarding/
  routing/app_router.dart   # go_router, AppRoutes string constants
  l10n/app_en.arb            # source of truth; gen/ is generated, don't hand-edit
```

Rules that must hold:

- **No `ui/` file imports a vendor SDK or platform channel directly**
  (CameraX, AVFoundation, ML Kit, OpenCV, `cunning_document_scanner`, etc.).
  Everything goes through a `domain/providers/*.dart` interface, wired up in
  `service_locator.dart`. Verify with `flutter analyze` after touching
  anything in `ui/features/**`.
- **Production capture** is `ModeAwareCaptureProvider` in
  `_selectCaptureProvider()`: documents and IDs use
  `CunningDocumentScannerCaptureProvider` (ML Kit Document Scanner on
  Android, VisionKit on iOS); books use `NativeCaptureProvider` (CameraX /
  AVFoundation) for one live still per shutter. `CameraPackageCaptureProvider`
  stays in the tree and is not registered. A document shutter calls
  `CapturePageUseCase.saveShot`: it stores the still and returns. Crop and
  filters run page by page in post-capture edit after the user taps Done,
  not during the shutter and not as a bulk step on Review. Book capture
  uses `ProcessBookSpreadUseCase.processSinglePage` (save as `processing`)
  then `enhanceSavedPage` on a serial background queue so the next shutter
  is not blocked; Done opens the existing Review screen (no post-capture
  crop/filter walk). Stills from the system scanner set
  `StillCapture.nativeReady`, which makes `processCapture` keep that
  already-cropped image.
- **Page detection and enhancement** are `NativeOpenCv*Provider` wrappers
  over the path-based vision channel `com.quizfactor.bookscanner/vision`,
  falling back to the Dart adapters when the plugin is missing or reports
  unavailable. Android pins `org.opencv:opencv:4.11.0` and runs detection
  in Kotlin (`OpenCvScanEngine`). iOS `VisionPlugin` reports unavailable
  until `scripts/fetch_opencv_ios.sh` links an OpenCV 4.11 xcframework.
  Do not send live frames through platform channels, and do not copy the
  gitignored GPLv3 `Document-Scanner/` clone or its OpenCV 3.1 binaries.
- **`ConversionApi`** is the server PDF conversion contract (Markdown,
  EPUB, searchable PDF). `BookScannerApiClient` is the only implementation.
  Page size and image quality stay on the phone.
- **Every new provider interface needs a fake** usable in tests and
  integration tests, plus a **contract test** that runs against any adapter
  implementing the interface. Existing contract tests:
  `test/data/scanner/capture_provider_contract_test.dart`,
  `test/data/ocr/ocr_provider_contract_test.dart`,
  `test/data/export/pdf_rasterizer_provider_contract_test.dart`.
  Detection, enhancement, book dewarp, and `ConversionApi` currently have
  unit or fallback tests rather than that contract shape — follow the
  contract shape for a new interface.
- **ViewModels are `ChangeNotifier`**, views use `ListenableBuilder`. Views
  take an optional injectable `viewModel` constructor parameter (null in
  production → built from `locator<>()`; tests pass a fake/real VM directly).
  This is how every existing feature is tested — follow it for new ones.
- **Routing** goes through `AppRoutes` string constants in
  `lib/routing/app_router.dart`, never raw path strings scattered in
  `context.push(...)` calls. Use `extra:` for passing non-path data (see
  the rescan flow's `pageId`, and `CropFlowMode.postCapture`, for real
  examples).
- **`ScanPage.copyWith` deliberately cannot change `originalImagePath`** —
  the original image is retained until the user explicitly deletes it. UI
  lists prefer `processedImagePath`. If you need to genuinely replace a
  page's image content (e.g. rescan), construct a new `ScanPage`
  explicitly; don't fight `copyWith` for this.

## Testing conventions

- Plain `flutter_test`. **No mocking library** — hand-rolled fakes via
  `implements`. Follow the existing fake style in `test/**/fakes` and the
  provider adapters under `lib/data/services/*/adapters`.
- Synthetic test images are built with `package:image`
  (`img.Image`, `img.fill`, `img.fillRect`, `img.fillPolygon`,
  `img.gaussianBlur`, `img.encodeJpg`) — never commit binary fixture images
  when a synthetic one will do.
- Tests needing real file I/O use `Directory.systemTemp.createTemp()` with a
  `tearDown` that deletes it. Tests needing app-private paths use
  `FakePathProviderPlatform` / `AppPaths.instance()`.
- If a widget test does real `dart:io` or `dart:ui.instantiateImageCodec`
  work, wrap it in `tester.runAsync()` or it will hang/misbehave inside
  `flutter_test`'s fake-async zone.
- **`context.pop()` / `context.go()` (go_router) requires a real `GoRouter`
  ancestor.** Most widget tests do not pump one. `unlock_screen_test.dart`
  does, for unlock navigation. Otherwise test the ViewModel directly with
  a plain `test()` (see `capture_screen_test.dart` for the rescan case) or
  cover it via an `integration_test/` end-to-end flow — don't try to fake
  a `BuildContext.pop()`.
- `integration_test/*.dart` files drive the real widget tree end to end with
  fake `CaptureProvider`/`OcrProvider` doubles registered via
  `service_locator.dart`'s `locator.unregister<T>()` /
  `locator.registerFactory<T>()`, and real file I/O. Use stable `ValueKey`s
  on every interactive widget (existing files show the pattern) so tests
  don't depend on text/layout. These need a real emulator/simulator/device
  to run — writing one without running it is only "written, not verified."
- `test/pipeline_corpus/` holds pipeline golden/regression tests against a
  synthetic image corpus (flat pages, curved books, glossy paper, shadows,
  fingers, skew, low light, multi-column, tables, illustrations, RTL) per
  SPEC-V1 — this is pixel/behavioral pipeline testing, **not** UI screenshot
  testing. Don't confuse the two.

Run before considering any task done:
```
flutter analyze
flutter test
```
Both must be clean. Run `flutter gen-l10n` after editing `lib/l10n/app_en.arb`
(this always prints an informational, non-error line — that's expected).

## Environment constraints specific to this project

- This is a git repository. `master` tracks `origin`
  (`git@github.com:brudex/BookScanner.git`). Use normal git commands. Don't
  `git init` again, and don't commit or push unless the user asks.
- `/Document-Scanner/` is gitignored. It is a GPLv3 behavioral reference
  with old OpenCV 3.1 binaries. Do not copy its source or binaries into
  this project.
- Android release signing currently reuses the debug keystore
  (`android/app/build.gradle.kts`), so `flutter build apk --debug` and
  `--release` are equivalently installable without a real keystore. Release
  APKs are arm64-only (`abiFilters` / JNI excludes).
- Host RAM on this machine oscillates and has previously dropped as low as
  ~60MB free, which has caused real ANRs/GC-churn when booting an Android
  emulator and stalled Gradle/Kotlin compiles. Check `vm_stat` before
  starting an emulator or a long Gradle test run. A one-shot bounded build
  (e.g. `flutter build apk`) is much lower-risk than booting an emulator —
  prefer it, and if genuinely low on memory, say so rather than attempting
  a risky boot silently.
- No physical iOS device, Apple signing identity, or second locale is
  available in this environment — several `IMPLEMENTATION_STATUS.md` rows
  are legitimately 🚫-blocked on these, not on missing code. Don't try to
  fake verification of these; say what's blocked and why. iOS OpenCV stays
  on the Dart fallback until the xcframework is linked and a device exists.

## Task tracking

Work is tracked against a numbered task list (referenced in
`IMPLEMENTATION_STATUS.md`'s section headers, e.g. "— task 8"). When you pick
up or complete a task, keep the doc and any task tracker in sync — don't let
them drift apart.

## Scope discipline

- Don't add abstractions, error handling, or fallbacks for scenarios the spec
  doesn't call for. Match the existing minimalism (`analysis_options.yaml`
  includes `flutter_lints` and excludes `build/**`, `android/**`, and
  `ios/**` — don't gold-plate lint config either).
- Prefer extending an existing pattern (mirror the nearest analogous
  ViewModel/Screen/provider) over inventing a new one. Nearly every feature
  in this codebase follows the same View/ViewModel/UseCase/Repository shape —
  new features should be indistinguishable in style from old ones.
- If a request is genuinely ambiguous or spec-and-code disagree, ask rather
  than guessing — but don't ask about things answerable by reading `SPEC.md`,
  `IMPLEMENTATION_STATUS.md`, or the surrounding code first.
