import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// Minimal [PermissionHandlerPlatform] fake for VM/widget tests, where no
/// real platform channel exists to answer camera-permission checks.
class FakePermissionHandlerPlatform extends PermissionHandlerPlatform {
  FakePermissionHandlerPlatform({
    this.statusToReturn = PermissionStatus.granted,
  });

  PermissionStatus statusToReturn;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      statusToReturn;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async => {for (final p in permissions) p: statusToReturn};

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async => false;

  @override
  Future<bool> openAppSettings() async => true;
}
