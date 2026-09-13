import 'dart:io';

import 'package:bookscanner/data/services/local/app_paths.dart';
import 'package:bookscanner/data/services/scanner/adapters/fake_capture_provider.dart';
import 'package:bookscanner/domain/models/capture_models.dart';
import 'package:bookscanner/domain/providers/capture_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_path_provider_platform.dart';

/// Contract test (SPEC 9.7): asserts the behavior every [CaptureProvider]
/// adapter must satisfy, independent of which concrete implementation is
/// under test. Currently exercised against [FakeCaptureProvider]; the same
/// suite should be pointed at the native Android/iOS adapters once they can
/// run in an instrumented/simulator environment (tracked in
/// IMPLEMENTATION_STATUS.md).
void runCaptureProviderContractTests(
  String label,
  CaptureProvider Function() build,
) {
  group('CaptureProvider contract ($label)', () {
    test('capabilities can be queried before a session is open', () async {
      final provider = build();
      final caps = await provider.capabilities();
      expect(caps, isNotNull);
    });

    test(
      'openSession then captureStill returns a real persisted file',
      () async {
        final provider = build();
        await provider.openSession(CaptureMode.singlePage);
        final still = await provider.captureStill();

        expect(File(still.originalImagePath).existsSync(), isTrue);
        expect(still.qualityScore, inInclusiveRange(0.0, 1.0));
        expect(still.providerInfo.providerName, isNotEmpty);

        await provider.closeSession();
      },
    );

    test('multiple captures in one session produce distinct files', () async {
      final provider = build();
      await provider.openSession(CaptureMode.batch);
      final first = await provider.captureStill();
      final second = await provider.captureStill();

      expect(first.originalImagePath, isNot(equals(second.originalImagePath)));
      expect(File(first.originalImagePath).existsSync(), isTrue);
      expect(File(second.originalImagePath).existsSync(), isTrue);

      await provider.closeSession();
    });

    test('analysisStream emits frame analyses while session is open', () async {
      final provider = build();
      await provider.openSession(CaptureMode.singlePage);

      final frame = await provider.analysisStream().first;
      expect(frame.timestampMs, greaterThan(0));

      await provider.closeSession();
    });

    test(
      'closeSession does not throw and can be called after captures',
      () async {
        final provider = build();
        await provider.openSession(CaptureMode.singlePage);
        await provider.captureStill();
        await provider.closeSession();
      },
    );

    test('previewAspectRatio is positive after openSession', () async {
      final provider = build();
      await provider.openSession(CaptureMode.singlePage);
      expect(provider.previewAspectRatio, greaterThan(0));
      await provider.closeSession();
    });

    test('captureStill reports still-analysis fields in range', () async {
      final provider = build();
      await provider.openSession(CaptureMode.singlePage);
      final still = await provider.captureStill();
      expect(still.detectionConfidence, inInclusiveRange(0.0, 1.0));
      await provider.closeSession();
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppPaths paths;
  late Directory tmpDir;

  setUpAll(() async {
    tmpDir = await Directory.systemTemp.createTemp('capture_contract_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tmpDir);
    paths = await AppPaths.instance();
  });

  tearDownAll(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  runCaptureProviderContractTests(
    'fake',
    () => FakeCaptureProvider(paths: paths),
  );
}
