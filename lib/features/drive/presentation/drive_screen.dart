import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants.dart';
import '../../../core/ffi/zyra_detection.dart';
import '../../../core/ffi/zyra_engine.dart';
import '../../../core/ffi/zyra_engine_provider.dart';
import '../../../core/permissions/permissions_service.dart';
import '../../vehicle_select/application/vehicle_profile_notifier.dart';
import '../../vehicle_select/data/vehicle_profile.dart';
import 'widgets/advanced_lane_overlay_painter.dart';
import 'widgets/detection_overlay_painter.dart';
import 'widgets/fcw_banner.dart';
import 'widgets/fps_bar.dart';
import 'widgets/lane_assist_hud.dart';
import 'widgets/lane_overlay_painter.dart';
import 'widgets/status_bar.dart';

/// Phase 5 — live camera preview + real-time YOLOv8 detection overlay.
///
/// Flow:
///   1. Request camera + location permissions on first build.
///   2. Once camera is granted, initialise the first back camera and start
///      an image stream.
///   3. Each `CameraImage` is copied into a native buffer (NV21 semi-planar)
///      and submitted to [ZyraEngine.submitFrame]. A 33 ms polling timer
///      drains the latest detection batch into UI state.
///   4. [DetectionOverlayPainter] rotates bbox coords from sensor-native
///      space into the display orientation of [CameraPreview] and draws
///      per-class colored rectangles + labels on top.
class DriveScreen extends ConsumerStatefulWidget {
  const DriveScreen({super.key});

  @override
  ConsumerState<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends ConsumerState<DriveScreen>
    with WidgetsBindingObserver {
  static const PermissionsService _permissions = PermissionsService();

  /// Minimum gap between consecutive `submitFrame` calls. The image stream
  /// can deliver at 60 FPS on some devices — we throttle to ~30 to avoid
  /// burning CPU on copies we'll never use. Native inference is throttled
  /// independently by the engine's worker thread.
  static const Duration _submitMinInterval = Duration(milliseconds: 33);

  DrivePermissionResult? _permissionResult;
  bool _requestingPermissions = false;

  CameraController? _controller;
  CameraDescription? _camera;
  bool _initialisingCamera = false;
  Object? _cameraError;
  bool _streamStarted = false;

  Timer? _pollTimer;
  ZyraBatch? _latest;
  int _frameId = 0;
  DateTime? _lastSubmit;
  ZyraLdwState _prevLdw = ZyraLdwState.disarmed;
  ZyraFcwState _prevFcw = ZyraFcwState.safe;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    // Drive screen locks to landscape-left. Landscape gives a wider
    // horizontal FoV on the camera (useful for catching merging traffic
    // and full lane boundaries) and a dashboard-style HUD layout.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: <SystemUiOverlay>[],
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _stopAndDisposeCamera();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? c = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      if (c != null && c.value.isStreamingImages) {
        // Best-effort stop; controller disposal happens on dispose().
        c.stopImageStream().catchError((_) {});
      }
    } else if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
      if (c != null && !c.value.isStreamingImages && _permissionResult?.cameraGranted == true) {
        _attachStream(c);
      }
    }
  }

  // ---------------------------------------------------------------------------
  //  Permissions
  // ---------------------------------------------------------------------------

  Future<void> _requestPermissions() async {
    if (_requestingPermissions) return;
    setState(() => _requestingPermissions = true);
    final DrivePermissionResult r = await _permissions.requestDrivePermissions();
    if (!mounted) return;
    setState(() {
      _permissionResult = r;
      _requestingPermissions = false;
    });
    if (r.cameraGranted && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _refreshPermissionStatus() async {
    final DrivePermissionResult r = await _permissions.checkDrivePermissions();
    if (!mounted) return;
    setState(() => _permissionResult = r);
    if (r.cameraGranted && _controller == null && !_initialisingCamera) {
      _initCamera();
    }
  }

  // ---------------------------------------------------------------------------
  //  Camera lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _initCamera() async {
    if (_initialisingCamera) return;
    _initialisingCamera = true;
    try {
      final List<CameraDescription> cams = await availableCameras();
      final CameraDescription back = cams.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      _camera = back;

      final CameraController c = CameraController(
        back,
        ResolutionPreset.high, // 720p on most devices — good balance
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      setState(() => _cameraError = null);
      // Phase 10 — push mount geometry now that we know the sensor
      // resolution. IPM needs sensor-native landscape dims, which
      // previewSize already reports in landscape on back cameras.
      unawaited(_pushCameraGeometry());
      _attachStream(c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = e);
    } finally {
      _initialisingCamera = false;
    }
  }

  /// Push the camera mount + optics geometry into the native engine so the
  /// IPM module can project pixels onto the road plane. No-op if any of
  /// the inputs (camera size, vehicle profile, engine handle) is still
  /// loading — the call is idempotent so it's safe to call again once
  /// things settle.
  Future<void> _pushCameraGeometry() async {
    final CameraController? c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final Size? preview = c.value.previewSize;
    if (preview == null) return;
    final VehicleProfile? profile =
        ref.read(vehicleProfileProvider).valueOrNull;
    if (profile == null) return;
    try {
      final ZyraEngine engine = await ref.read(zyraEngineProvider.future);
      if (!mounted) return;
      engine.setCameraGeometry(
        mountHeightM: profile.mountHeightM,
        pitchDeg: 0.0,
        hfovDeg: kDefaultHfovDeg,
        frameW: preview.width.round(),
        frameH: preview.height.round(),
      );
    } catch (e) {
      if (mounted) debugPrint('[Zyra] set_camera_geometry failed: $e');
    }
  }

  void _attachStream(CameraController c) {
    if (_streamStarted && c.value.isStreamingImages) return;
    _streamStarted = true;
    c.startImageStream(_onCameraImage).catchError((Object e) {
      if (mounted) setState(() => _cameraError = e);
    });
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final ZyraEngine? eng = ref.read(zyraEngineProvider).valueOrNull;
      if (eng == null || !mounted) return;
      final ZyraBatch? b = eng.pollDetections();
      if (b != null) {
        _maybeHaptic(b.assist.state);
        _maybeFcwHaptic(b.fcw.state);
        setState(() => _latest = b);
      }
    });
  }

  /// Fire a short haptic buzz on rising LDW transitions — once per
  /// DISARMED/ARMED → WARN, and a heavier pulse on WARN → ALERT. We
  /// deliberately don't re-fire while staying in the same state, else the
  /// phone would vibrate at every frame.
  void _maybeHaptic(ZyraLdwState next) {
    if (next == _prevLdw) return;
    final ZyraLdwState prev = _prevLdw;
    _prevLdw = next;
    if (next == ZyraLdwState.alert && prev != ZyraLdwState.alert) {
      HapticFeedback.heavyImpact();
    } else if (next == ZyraLdwState.warn && prev == ZyraLdwState.armed) {
      HapticFeedback.mediumImpact();
    }
  }

  /// FCW haptics — fires once per rising-severity transition. A collision
  /// cue must not disappear into a spurious taptic pattern, so the ALERT
  /// buzz is always `heavyImpact`; WARN uses `mediumImpact`; CAUTION is
  /// visual-only to stay out of the driver's way on routine tailgating.
  void _maybeFcwHaptic(ZyraFcwState next) {
    if (next == _prevFcw) return;
    final ZyraFcwState prev = _prevFcw;
    _prevFcw = next;
    final int nextRank = next.index;
    final int prevRank = prev.index;
    if (nextRank <= prevRank) return;
    if (next == ZyraFcwState.alert) {
      HapticFeedback.heavyImpact();
    } else if (next == ZyraFcwState.warn) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _stopAndDisposeCamera() async {
    final CameraController? c = _controller;
    _controller = null;
    _streamStarted = false;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  //  Frame submission
  // ---------------------------------------------------------------------------

  void _onCameraImage(CameraImage img) {
    final DateTime now = DateTime.now();
    if (_lastSubmit != null && now.difference(_lastSubmit!) < _submitMinInterval) {
      return;
    }
    _lastSubmit = now;

    final ZyraEngine? eng = ref.read(zyraEngineProvider).valueOrNull;
    if (eng == null) return;
    if (img.planes.length < 3) return;

    final int w = img.width;
    final int h = img.height;
    final Plane yPlane = img.planes[0];
    final Plane uPlane = img.planes[1];
    final Plane vPlane = img.planes[2];
    final int uvPixelStride = uPlane.bytesPerPixel ?? 2;

    // Pack into a single native buffer: Y block (W*H) + chroma block
    // (W*(H/2) for semi-planar, W*H/2 for planar I420).
    //
    // For semi-planar (pixelStride=2 — NV21/NV12), we take plane[2].bytes
    // (V-starting stream) which matches NV21 layout on the vast majority
    // of Android devices (including our Realme target). We then set
    // u = uv+1, v = uv so that engine.cpp's `v < u` heuristic selects
    // COLOR_YUV2RGB_NV21. On an NV12 device, this costs us a 1-pixel
    // horizontal shift of U samples — noticeable only as a small color
    // tint, YOLO still detects correctly.
    //
    // For planar I420 (pixelStride=1), we pack U-then-V into the chroma
    // block and let engine.cpp's I420 path handle it.
    final int ySize = w * h;
    final int uvRows = h ~/ 2;
    final int uvCols = w ~/ 2;
    final int chromaSize = uvPixelStride == 2 ? w * uvRows : 2 * uvCols * uvRows;
    final int total = ySize + chromaSize;

    final ffi.Pointer<ffi.Uint8> buf = malloc<ffi.Uint8>(total);
    try {
      _packY(yPlane, buf, w, h);
      if (uvPixelStride == 2) {
        _packSemiPlanar(vPlane, buf + ySize, w, uvRows);
      } else {
        _packI420(uPlane, vPlane, buf + ySize, uvCols, uvRows);
      }

      final int sensorOrientation = _camera?.sensorOrientation ?? 0;
      _frameId += 1;
      eng.submitFrame(
        y: buf,
        u: uvPixelStride == 2 ? buf + ySize + 1 : buf + ySize,
        v: uvPixelStride == 2 ? buf + ySize : buf + ySize + uvCols * uvRows,
        width: w,
        height: h,
        yRowStride: w,
        uvRowStride: uvPixelStride == 2 ? w : uvCols,
        uvPixelStride: uvPixelStride,
        rotationDeg: sensorOrientation,
        frameId: _frameId,
        timestampMs: now.millisecondsSinceEpoch.toDouble(),
      );
    } finally {
      malloc.free(buf);
    }
  }

  void _packY(
      Plane y, ffi.Pointer<ffi.Uint8> dst, int width, int height) {
    final Uint8List dstList = dst.asTypedList(width * height);
    final Uint8List src = y.bytes;
    if (y.bytesPerRow == width) {
      dstList.setRange(0, width * height, src);
      return;
    }
    // Strip row-stride padding.
    final int rowStride = y.bytesPerRow;
    for (int r = 0; r < height; r++) {
      final int srcOff = r * rowStride;
      final int dstOff = r * width;
      dstList.setRange(dstOff, dstOff + width, src, srcOff);
    }
  }

  void _packSemiPlanar(Plane v, ffi.Pointer<ffi.Uint8> dst,
      int width, int uvRows) {
    // Target: W × uvRows bytes of VU-interleaved (NV21) data.
    final int bytes = width * uvRows;
    final Uint8List dstList = dst.asTypedList(bytes);
    final Uint8List src = v.bytes;
    final int rowStride = v.bytesPerRow;
    if (rowStride == width && src.length >= bytes) {
      dstList.setRange(0, bytes, src);
      return;
    }
    for (int r = 0; r < uvRows; r++) {
      final int srcOff = r * rowStride;
      final int dstOff = r * width;
      final int maxCopy = src.length - srcOff;
      final int toCopy = maxCopy >= width ? width : (maxCopy > 0 ? maxCopy : 0);
      if (toCopy > 0) {
        dstList.setRange(dstOff, dstOff + toCopy, src, srcOff);
      }
    }
  }

  void _packI420(Plane u, Plane v, ffi.Pointer<ffi.Uint8> dst,
      int uvCols, int uvRows) {
    // Layout in native buffer: U plane then V plane, each contiguous
    // (rowStride = uvCols).
    final int plane = uvCols * uvRows;
    final Uint8List uDst = dst.asTypedList(plane);
    final Uint8List vDst = (dst + plane).asTypedList(plane);
    _copyPlaneRows(u, uDst, uvCols, uvRows);
    _copyPlaneRows(v, vDst, uvCols, uvRows);
  }

  void _copyPlaneRows(Plane p, Uint8List dst, int cols, int rows) {
    final Uint8List src = p.bytes;
    final int rowStride = p.bytesPerRow;
    if (rowStride == cols && src.length >= cols * rows) {
      dst.setRange(0, cols * rows, src);
      return;
    }
    for (int r = 0; r < rows; r++) {
      final int srcOff = r * rowStride;
      final int dstOff = r * cols;
      final int maxCopy = src.length - srcOff;
      final int toCopy = maxCopy >= cols ? cols : (maxCopy > 0 ? maxCopy : 0);
      if (toCopy > 0) {
        dst.setRange(dstOff, dstOff + toCopy, src, srcOff);
      }
    }
  }

  // ---------------------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AsyncValue<VehicleProfile?> profileAsync =
        ref.watch(vehicleProfileProvider);
    final AsyncValue<ZyraEngine> engineAsync = ref.watch(zyraEngineProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Drive'),
        backgroundColor: Colors.black.withValues(alpha: 0.35),
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
      extendBodyBehindAppBar: true,
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('$e')),
        data: (VehicleProfile? profile) {
          if (profile == null) {
            return const Center(child: Text('No vehicle selected.'));
          }
          final bool cameraGranted =
              _permissionResult?.cameraGranted ?? false;
          if (!cameraGranted) {
            return SafeArea(
              child: _PermissionPanel(
                result: _permissionResult,
                requesting: _requestingPermissions,
                onRetry: _requestPermissions,
              ),
            );
          }
          return _LiveView(
            controller: _controller,
            camera: _camera,
            cameraError: _cameraError,
            engineAsync: engineAsync,
            latest: _latest,
            profile: profile,
          );
        },
      ),
    );
  }
}

// =============================================================================
//  Live preview + overlay
// =============================================================================

class _LiveView extends StatelessWidget {
  const _LiveView({
    required this.controller,
    required this.camera,
    required this.cameraError,
    required this.engineAsync,
    required this.latest,
    required this.profile,
  });

  final CameraController? controller;
  final CameraDescription? camera;
  final Object? cameraError;
  final AsyncValue<ZyraEngine> engineAsync;
  final ZyraBatch? latest;
  final VehicleProfile profile;

  @override
  Widget build(BuildContext context) {
    if (cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera failed to start:\n$cameraError',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final CameraController? c = controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    if (engineAsync.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Starting perception engine…',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    final ZyraEngine? engine = engineAsync.valueOrNull;
    if (engine == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Engine unavailable:\n${engineAsync.error}',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Sensor-native size is reported by the plugin as landscape
    // (width > height on back cameras in portrait UI).
    final Size preview = c.value.previewSize ?? const Size(1280, 720);
    final int sensorOrientation = camera?.sensorOrientation ?? 90;
    final bool isFront = camera?.lensDirection == CameraLensDirection.front;
    final AdasColors adas = Theme.of(context).extension<AdasColors>()!;

    // Drive screen is locked to DeviceOrientation.landscapeLeft which rotates
    // the display 90° relative to the phone's portrait-up orientation. The
    // painters' rotation math is authored against a portrait display, so we
    // subtract 90° up front: back-camera sensors (sensorOrientation == 90)
    // then need no further rotation, matching the physical reality that the
    // sensor's native frame is already landscape.
    const int displayRotationDeg = 90;
    final int effectiveSensorOrientation =
        (sensorOrientation - displayRotationDeg + 360) % 360;
    final bool landscapeSensorToLandscapeDisplay =
        effectiveSensorOrientation == 0 || effectiveSensorOrientation == 180;
    final double displayAspect = landscapeSensorToLandscapeDisplay
        ? preview.width / preview.height
        : preview.height / preview.width;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: AspectRatio(
            aspectRatio: displayAspect,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CameraPreview(c),
                // Raw Hough segments — kept as a faint debug under-layer so
                // the tracker's smoothed curves can be visually compared
                // against the raw detector output.
                Positioned.fill(
                  child: CustomPaint(
                    painter: LaneOverlayPainter(
                      batch: latest,
                      sensorWidth: preview.width,
                      sensorHeight: preview.height,
                      sensorOrientation: effectiveSensorOrientation,
                      mirror: isFront,
                    ),
                  ),
                ),
                // Phase 7 — smoothed polynomial lane curves + drift wedge.
                Positioned.fill(
                  child: CustomPaint(
                    painter: AdvancedLaneOverlayPainter(
                      batch: latest,
                      sensorWidth: preview.width,
                      sensorHeight: preview.height,
                      sensorOrientation: effectiveSensorOrientation,
                      mirror: isFront,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: DetectionOverlayPainter(
                      batch: latest,
                      sensorWidth: preview.width,
                      sensorHeight: preview.height,
                      sensorOrientation: effectiveSensorOrientation,
                      adas: adas,
                      mirror: isFront,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FpsBar(
                  fps: engine.avgFps,
                  vulkanActive: engine.vulkanActive == 1,
                  vehicleName: profile.displayName,
                ),
                if (latest != null && latest!.fcw.isActive)
                  FcwBanner(fcw: latest!.fcw),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: LaneAssistHud(batch: latest),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: StatusBar(
              detections: latest?.detections.length ?? 0,
              lanes: latest?.lanes.length ?? 0,
              totalMs: latest?.totalMs ?? 0,
              inferMs: latest?.inferMs ?? 0,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
//  Permissions panel (pre-live)
// =============================================================================

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.result,
    required this.requesting,
    required this.onRetry,
  });

  final DrivePermissionResult? result;
  final bool requesting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool cameraOk = result?.cameraGranted ?? false;
    final bool locationOk = result?.locationGranted ?? false;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 16),
          Text('Permissions needed', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          _PermissionRow(label: 'Camera', granted: cameraOk, required: true),
          const SizedBox(height: 8),
          _PermissionRow(
              label: 'Location', granted: locationOk, required: false),
          const SizedBox(height: 24),
          if (requesting)
            const Center(child: CircularProgressIndicator())
          else
            Center(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Request again'),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Camera access is required for perception. Location is optional '
            'and unlocks GPS-based speed + heading in later phases.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: ZyraTheme.onSurfaceMuted),
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
