import 'package:flutter/services.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

/// Minimal [LocalAuthPlatform] fake for VM/widget tests, where no real
/// platform channel exists to answer biometric/PIN authentication requests
/// -- the real `LocalAuthentication().authenticate(...)` call never resolves
/// under `flutter_test` with no platform implementation registered (unlike
/// a classic unmocked `MethodChannel`, which throws `MissingPluginException`
/// immediately, this Pigeon-based plugin just hangs), so this fake is the
/// only way to exercise both the success and failure paths deterministically.
class FakeLocalAuthPlatform extends LocalAuthPlatform {
  FakeLocalAuthPlatform({this.authenticateResult = true, this.throwOnAuthenticate = false});

  bool authenticateResult;
  bool throwOnAuthenticate;
  int authenticateCalls = 0;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const [],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authenticateCalls++;
    if (throwOnAuthenticate) {
      throw PlatformException(code: 'auth_error', message: 'test failure');
    }
    return authenticateResult;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async => true;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => const [
    BiometricType.strong,
  ];

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> stopAuthentication() async => true;
}
