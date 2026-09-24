import 'package:bookscanner/ui/core/app_lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts locked', () {
    final controller = AppLockController();
    expect(controller.unlockedThisSession, isFalse);
  });

  test('unlock flips the flag and notifies once', () {
    final controller = AppLockController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.unlock();

    expect(controller.unlockedThisSession, isTrue);
    expect(notifications, 1);

    // Calling unlock again while already unlocked is a no-op.
    controller.unlock();
    expect(notifications, 1);
  });

  test('lock flips the flag back and notifies once', () {
    final controller = AppLockController()..unlock();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.lock();

    expect(controller.unlockedThisSession, isFalse);
    expect(notifications, 1);

    // Calling lock again while already locked is a no-op.
    controller.lock();
    expect(notifications, 1);
  });
}
