import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/models/capture_models.dart';
import '../../domain/repositories/settings_repository.dart';
import '../services/local/database_service.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._databaseService);

  static const _rowId = 'app_settings';

  final DatabaseService _databaseService;
  final _changes = StreamController<AppSettings>.broadcast();

  Database get _db => _databaseService.db;

  @override
  Stream<AppSettings> watchSettings() async* {
    yield await getSettings();
    yield* _changes.stream;
  }

  @override
  Future<AppSettings> getSettings() async {
    final rows = await _db.query(
      'settings',
      where: 'id = ?',
      whereArgs: [_rowId],
    );
    if (rows.isEmpty) return const AppSettings();
    return _fromJson(
      jsonDecode(rows.first['value']! as String) as Map<String, Object?>,
    );
  }

  @override
  Future<void> updateSettings(AppSettings settings) async {
    await _db.insert('settings', {
      'id': _rowId,
      'value': jsonEncode(_toJson(settings)),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(settings);
  }

  static Map<String, Object?> _toJson(AppSettings s) => {
    'appLockEnabled': s.appLockEnabled,
    'cloudProcessingConsentGiven': s.cloudProcessingConsentGiven,
    'cloudProcessingConsentAtMs': s.cloudProcessingConsentAtMs,
    'modelTrainingOptIn': s.modelTrainingOptIn,
    'stripLocationMetadata': s.stripLocationMetadata,
    'ocrLanguages': s.ocrLanguages,
    'hasSeenCopyrightNotice': s.hasSeenCopyrightNotice,
    'largeExportAcknowledgedPageThreshold':
        s.largeExportAcknowledgedPageThreshold,
    'hasCompletedOnboarding': s.hasCompletedOnboarding,
    'captureSettings': {
      'autoCaptureEnabled': s.captureSettings.autoCaptureEnabled,
      'countdownSeconds': s.captureSettings.countdownSeconds,
      'continuousCapture': s.captureSettings.continuousCapture,
      'hapticConfirmation': s.captureSettings.hapticConfirmation,
      'audioConfirmation': s.captureSettings.audioConfirmation,
      'flashMode': s.captureSettings.flashMode.name,
    },
  };

  static AppSettings _fromJson(Map<String, Object?> json) {
    final cs = (json['captureSettings'] as Map?)?.cast<String, Object?>();
    return AppSettings(
      appLockEnabled: json['appLockEnabled'] as bool? ?? false,
      cloudProcessingConsentGiven:
          json['cloudProcessingConsentGiven'] as bool? ?? false,
      cloudProcessingConsentAtMs: json['cloudProcessingConsentAtMs'] as int?,
      modelTrainingOptIn: json['modelTrainingOptIn'] as bool? ?? false,
      stripLocationMetadata: json['stripLocationMetadata'] as bool? ?? true,
      ocrLanguages:
          (json['ocrLanguages'] as List?)?.cast<String>() ?? const ['en'],
      hasSeenCopyrightNotice: json['hasSeenCopyrightNotice'] as bool? ?? false,
      largeExportAcknowledgedPageThreshold:
          json['largeExportAcknowledgedPageThreshold'] as int? ?? 300,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      captureSettings: cs == null
          ? const CaptureSettings()
          : CaptureSettings(
              autoCaptureEnabled: cs['autoCaptureEnabled'] as bool? ?? true,
              countdownSeconds: cs['countdownSeconds'] as int? ?? 0,
              continuousCapture: cs['continuousCapture'] as bool? ?? false,
              hapticConfirmation: cs['hapticConfirmation'] as bool? ?? true,
              audioConfirmation: cs['audioConfirmation'] as bool? ?? true,
              flashMode: FlashMode.values.byName(
                cs['flashMode'] as String? ?? 'off',
              ),
            ),
    );
  }
}
