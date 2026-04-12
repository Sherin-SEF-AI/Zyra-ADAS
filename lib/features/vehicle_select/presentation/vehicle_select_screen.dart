import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../application/vehicle_profile_notifier.dart';
import '../data/vehicle_profile.dart';
import 'widgets/vehicle_card.dart';

/// First-run vehicle selection. On entry:
///   - if a profile is already persisted → jump straight to /drive.
///   - otherwise → show the card list and wait for a tap.
class VehicleSelectScreen extends ConsumerStatefulWidget {
  const VehicleSelectScreen({super.key});

  @override
  ConsumerState<VehicleSelectScreen> createState() =>
      _VehicleSelectScreenState();
}

class _VehicleSelectScreenState
    extends ConsumerState<VehicleSelectScreen> {
  VehicleProfile? _pendingSelection;
  bool _forwarded = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<VehicleProfile?> profileAsync =
        ref.watch(vehicleProfileProvider);

    // If we already have a persisted profile, skip the picker entirely.
    ref.listen<AsyncValue<VehicleProfile?>>(vehicleProfileProvider,
        (AsyncValue<VehicleProfile?>? prev, AsyncValue<VehicleProfile?> next) {
      next.whenData((VehicleProfile? profile) {
        if (profile != null && !_forwarded) {
          _forwarded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed(ZyraRoutes.drive);
          });
        }
      });
    });

    return Scaffold(
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (Object err, StackTrace st) => _ErrorView(error: err),
          data: (VehicleProfile? persisted) {
            // If persisted non-null we're about to route away; render splash
            // placeholder rather than flash the picker.
            if (persisted != null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _Picker(
              selection: _pendingSelection,
              onSelect: (VehicleProfile p) =>
                  setState(() => _pendingSelection = p),
              onConfirm: _pendingSelection == null
                  ? null
                  : () async {
                      await ref
                          .read(vehicleProfileProvider.notifier)
                          .select(_pendingSelection!);
                    },
            );
          },
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.selection,
    required this.onSelect,
    required this.onConfirm,
  });

  final VehicleProfile? selection;
  final ValueChanged<VehicleProfile> onSelect;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<VehicleProfile> profiles = VehicleProfile.all();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'ZYRA',
            style: theme.textTheme.displayLarge?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your vehicle',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Zyra tunes its shadow planners to your vehicle\'s geometry and '
            'dynamics. Pick the closest match — you can change this later in '
            'Settings.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ZyraTheme.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              itemCount: profiles.length,
              separatorBuilder: (BuildContext _, int index) =>
                  const SizedBox(height: 16),
              itemBuilder: (BuildContext ctx, int i) {
                final VehicleProfile p = profiles[i];
                return VehicleCard(
                  profile: p,
                  selected: selection == p,
                  onTap: () => onSelect(p),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onConfirm,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48, color: ZyraTheme.danger),
            const SizedBox(height: 12),
            Text(
              'Could not load vehicle profile.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
