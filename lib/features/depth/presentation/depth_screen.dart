import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/zyra_detection.dart';
import '../../../core/ffi/zyra_engine.dart';
import '../../../core/ffi/zyra_engine_provider.dart';
import 'widgets/depth_colormap_painter.dart';

/// Separate depth visualization screen — renders a real-time plasma colormap
/// of the Depth Anything V2 output over the camera preview.
class DepthScreen extends ConsumerStatefulWidget {
  const DepthScreen({super.key});

  @override
  ConsumerState<DepthScreen> createState() => _DepthScreenState();
}

class _DepthScreenState extends ConsumerState<DepthScreen> {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _initialisingCamera = false;
  bool _streamStarted = false;
  Timer? _pollTimer;
  ZyraBatch? _latest;
  int _frameId = 0;
  DateTime? _lastSubmit;
  double _opacity = 0.75;

  static const Duration _submitMinInterval = Duration(milliseconds: 50);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: <SystemUiOverlay>[],
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stopAndDisposeCamera();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

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
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      setState(() {});
      _attachStream(c);
    } catch (e) {
      if (mounted) {
        setState(() {});
      }
    } finally {
      _initialisingCamera = false;
    }
  }

  void _attachStream(CameraController c) {
    if (_streamStarted) return;
    _streamStarted = true;
    c.startImageStream(_onCameraImage);
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final ZyraEngine? eng = ref.read(zyraEngineProvider).valueOrNull;
      if (eng == null || !mounted) return;
      final ZyraBatch? b = eng.pollDetections();
      if (b != null) {
        setState(() => _latest = b);
      }
    });
  }

  void _onCameraImage(CameraImage img) {
    final DateTime now = DateTime.now();
    if (_lastSubmit != null &&
        now.difference(_lastSubmit!) < _submitMinInterval) {
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

    final int ySize = w * h;
    final int uvRows = h ~/ 2;
    final int uvCols = w ~/ 2;
    final int chromaSize =
        uvPixelStride == 2 ? w * uvRows : 2 * uvCols * uvRows;
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
        v: uvPixelStride == 2
            ? buf + ySize
            : buf + ySize + uvCols * uvRows,
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

  void _packY(Plane y, ffi.Pointer<ffi.Uint8> dst, int width, int height) {
    final Uint8List dstList = dst.asTypedList(width * height);
    final Uint8List src = y.bytes;
    if (y.bytesPerRow == width) {
      dstList.setRange(0, width * height, src);
      return;
    }
    final int rowStride = y.bytesPerRow;
    for (int r = 0; r < height; r++) {
      dstList.setRange(r * width, r * width + width, src, r * rowStride);
    }
  }

  void _packSemiPlanar(
      Plane v, ffi.Pointer<ffi.Uint8> dst, int width, int uvRows) {
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
      if (toCopy > 0) dstList.setRange(dstOff, dstOff + toCopy, src, srcOff);
    }
  }

  void _packI420(Plane u, Plane v, ffi.Pointer<ffi.Uint8> dst, int uvCols,
      int uvRows) {
    final int plane = uvCols * uvRows;
    _copyPlaneRows(u, dst.asTypedList(plane), uvCols, uvRows);
    _copyPlaneRows(v, (dst + plane).asTypedList(plane), uvCols, uvRows);
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
      if (toCopy > 0) dst.setRange(dstOff, dstOff + toCopy, src, srcOff);
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

  @override
  Widget build(BuildContext context) {
    final CameraController? c = _controller;
    final bool ready = c != null && c.value.isInitialized;

    final Size preview =
        ready ? (c.value.previewSize ?? const Size(1280, 720)) : Size.zero;
    final int sensorOrientation = _camera?.sensorOrientation ?? 90;
    const int displayRotationDeg = 90;
    final int effectiveSensorOrientation =
        (sensorOrientation - displayRotationDeg + 360) % 360;
    final bool landscapeSensor =
        effectiveSensorOrientation == 0 || effectiveSensorOrientation == 180;
    final double displayAspect = ready
        ? (landscapeSensor
            ? preview.width / preview.height
            : preview.height / preview.width)
        : 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Depth View'),
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        actions: <Widget>[
          // Opacity slider.
          SizedBox(
            width: 140,
            child: Slider(
              value: _opacity,
              min: 0.3,
              max: 1.0,
              onChanged: (double v) => setState(() => _opacity = v),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Center(
                  child: AspectRatio(
                    aspectRatio: displayAspect,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CameraPreview(c),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: DepthColormapPainter(
                              batch: _latest,
                              sensorWidth: preview.width,
                              sensorHeight: preview.height,
                              sensorOrientation: effectiveSensorOrientation,
                              mirror: false,
                              opacity: _opacity,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Timing info overlay.
                if (_latest != null && _latest!.hasDepth)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Depth: ${_latest!.depthInferMs.toStringAsFixed(0)}ms infer '
                        '+ ${_latest!.depthPostMs.toStringAsFixed(0)}ms post '
                        '| ${_latest!.depthMapW}x${_latest!.depthMapH}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
