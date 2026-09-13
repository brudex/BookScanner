import 'package:bookscanner/data/repositories/settings_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  test('getSettings returns defaults when nothing saved', () async {
    final db = await openTestDatabase();
    final repository = SettingsRepositoryImpl(db);
    final settings = await repository.getSettings();
    expect(settings.appLockEnabled, isFalse);
    expect(settings.ocrLanguages, ['en']);
    expect(settings.stripLocationMetadata, isTrue);
  });

  test('updateSettings persists and round-trips all fields', () async {
    final db = await openTestDatabase();
    final repository = SettingsRepositoryImpl(db);
    final initial = await repository.getSettings();

    final updated = initial.copyWith(
      appLockEnabled: true,
      cloudProcessingConsentGiven: true,
      ocrLanguages: ['en', 'fr'],
      hasSeenCopyrightNotice: true,
    );
    await repository.updateSettings(updated);

    final fetched = await repository.getSettings();
    expect(fetched.appLockEnabled, isTrue);
    expect(fetched.cloudProcessingConsentGiven, isTrue);
    expect(fetched.ocrLanguages, ['en', 'fr']);
    expect(fetched.hasSeenCopyrightNotice, isTrue);
  });

  test('watchSettings emits current then subsequent updates', () async {
    final db = await openTestDatabase();
    final repository = SettingsRepositoryImpl(db);
    final stream = repository.watchSettings();

    final events = <bool>[];
    final sub = stream.listen((s) => events.add(s.appLockEnabled));
    await Future<void>.delayed(Duration.zero);

    final settings = await repository.getSettings();
    await repository.updateSettings(settings.copyWith(appLockEnabled: true));
    await Future<void>.delayed(Duration.zero);

    expect(events, [false, true]);
    await sub.cancel();
  });
}
