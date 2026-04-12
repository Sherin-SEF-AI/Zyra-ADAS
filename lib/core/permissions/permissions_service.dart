import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper over `permission_handler` that groups the permissions Zyra
/// actually asks for. Kept deliberately minimal — the UI layer doesn't care
/// about individual platform-channel oddities.
class PermissionsService {
  const PermissionsService();

  /// Ask for the permissions required by the drive screen. Camera is blocking
  /// (the app cannot function without it); location is soft (we can still run
  /// perception-only mode without GPS speed / heading in early phases).
  Future<DrivePermissionResult> requestDrivePermissions() async {
    final Map<Permission, PermissionStatus> statuses =
        await <Permission>[
      Permission.camera,
      Permission.location,
    ].request();

    return DrivePermissionResult(
      camera: statuses[Permission.camera] ?? PermissionStatus.denied,
      location: statuses[Permission.location] ?? PermissionStatus.denied,
    );
  }

  Future<DrivePermissionResult> checkDrivePermissions() async {
    return DrivePermissionResult(
      camera: await Permission.camera.status,
      location: await Permission.location.status,
    );
  }
}

class DrivePermissionResult {
  const DrivePermissionResult({
    required this.camera,
    required this.location,
  });

  final PermissionStatus camera;
  final PermissionStatus location;

  bool get cameraGranted => camera.isGranted;
  bool get locationGranted => location.isGranted;

  /// Camera is a hard requirement; location is not.
  bool get canStartDrive => cameraGranted;
}
