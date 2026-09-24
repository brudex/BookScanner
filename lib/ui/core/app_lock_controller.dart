import 'package:flutter/foundation.dart';

/// Transient (never persisted) "unlocked this app launch" state for
/// [AppSettings.appLockEnabled] (SPEC 6.9). Shared between the router's
/// redirect (which sends to `/unlock` when locked) and the app-lifecycle
/// observer in `main.dart` (which re-locks on background/resume) — neither
/// of those is a widget with its own state to hold this, so it lives here as
/// a singleton registered in the service locator.
class AppLockController extends ChangeNotifier {
  bool _unlockedThisSession = false;
  bool get unlockedThisSession => _unlockedThisSession;

  void unlock() {
    if (_unlockedThisSession) return;
    _unlockedThisSession = true;
    notifyListeners();
  }

  void lock() {
    if (!_unlockedThisSession) return;
    _unlockedThisSession = false;
    notifyListeners();
  }
}
