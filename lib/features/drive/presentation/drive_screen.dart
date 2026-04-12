import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/permissions/permissions_service.dart';
import '../../vehicle_select/application/vehicle_profile_notifier.dart';
import '../../vehicle_select/data/vehicle_profile.dart';

/// Phase 1 stub — proves routing, profile persistence, and permission flow.
/// The real camera preview + detection overlay lands in Phase 5; this screen
/// is intentionally minimal until the native engine is online.
class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key});

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen>
    with WidgetsBindingObserver {
  static const PermissionsService _permissions = PermissionsService();

  DrivePermissionResult? _permissionResult;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final DrivePermissionResult result =
        await _permissions.requestDrivePermissions();
    if (!mounted) return;
    setState(() {
      _permissionResult = result;
      _requesting = false;
    });
  }

  Future<void> _refreshPermissionStatus() async {
    final DrivePermissionResult result =
        await _permissions.checkDrivePermissions();
    if (!mounted) return;
    setState(() => _permissionResult = result);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<VehicleProfile?> profileAsync =
        ref.watch(vehicleProfileProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Engine debug',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed(ZyraRoutes.engineDebug);
            },
          ),
          IconButton(
            tooltip: 'Change vehicle',
            icon: const Icon(Icons.directions_car_outlined),
            onPressed: () async {
              await ref.read(vehicleProfileProvider.notifier).clear();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushReplacementNamed(ZyraRoutes.vehicleSelect);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: profileAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (Object e, _) => Center(child: Text('$e')),
            data: (VehicleProfile? profile) {
              if (profile == null) {
                // Should not happen — router guards against this — but fall
                // back gracefully rather than crash.
                return const Center(
                  child: Text('No vehicle selected.'),
                );
              }
              return _DriveStub(
                profile: profile,
                permissions: _permissionResult,
                requesting: _requesting,
                onRetry: _requestPermissions,
                theme: theme,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DriveStub extends StatelessWidget {
  const _DriveStub({
    required this.profile,
    required this.permissions,
    required this.requesting,
    required this.onRetry,
    required this.theme,
  });

  final VehicleProfile profile;
  final DrivePermissionResult? permissions;
  final bool requesting;
  final VoidCallback onRetry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Vehicle profile',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ZyraTheme.onSurfaceMuted,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(profile.displayName, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 24),
        _PermissionCard(
          permissions: permissions,
          requesting: requesting,
          onRetry: onRetry,
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ZyraTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ZyraTheme.outline),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.construction_rounded,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Camera preview + live detection land in Phase 5.\n'
                  'This stub confirms routing, profile persistence, and '
                  'permission handling are wired up correctly.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.permissions,
    required this.requesting,
    required this.onRetry,
  });

  final DrivePermissionResult? permissions;
  final bool requesting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool cameraOk = permissions?.cameraGranted ?? false;
    final bool locationOk = permissions?.locationGranted ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZyraTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZyraTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Permissions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _PermissionRow(
            label: 'Camera',
            granted: cameraOk,
            required: true,
          ),
          const SizedBox(height: 8),
          _PermissionRow(
            label: 'Location',
            granted: locationOk,
            required: false,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              if (requesting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Re-request'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.granted,
    required this.required,
  });

  final String label;
  final bool granted;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = granted
        ? ZyraTheme.success
        : (required ? ZyraTheme.danger : ZyraTheme.warning);
    return Row(
      children: <Widget>[
        Icon(
          granted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(label, style: theme.textTheme.bodyLarge),
        const SizedBox(width: 8),
        if (required && !granted)
          Text('(required)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: ZyraTheme.danger)),
        if (!required)
          Text('(optional)',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: ZyraTheme.onSurfaceMuted)),
      ],
    );
  }
}
