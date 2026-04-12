import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/ffi/zyra_detection.dart';
import '../../../core/ffi/zyra_engine.dart';
import '../../../core/ffi/zyra_engine_provider.dart';

/// Hidden Phase 4 debug surface — pushes a synthetic 640² grey frame
/// through submitFrame → pollDetections at ~30 Hz and renders the most
/// recent batch. Used to validate the FFI round-trip before the real
/// camera is wired in Phase 5.
class EngineDebugScreen extends ConsumerStatefulWidget {
  const EngineDebugScreen({super.key});

  @override
  ConsumerState<EngineDebugScreen> createState() => _EngineDebugScreenState();
}

class _EngineDebugScreenState extends ConsumerState<EngineDebugScreen> {
  Timer? _submitTimer;
  Timer? _pollTimer;
  int _frameId = 0;
  ZyraBatch? _latest;
  late Uint8List _grey;

  @override
  void initState() {
    super.initState();
    // Fill a grey 640² luma plane once. Chroma is synthesised on every
    // submit (fixed at 128 by ZyraEngine.submitRgbAsGrey — produces pure
    // grey RGB with no trivial YOLO signal).
    _grey = Uint8List(640 * 640)..fillRange(0, 640 * 640, 128);
  }

  void _startLoops(ZyraEngine engine) {
    _submitTimer?.cancel();
    _pollTimer?.cancel();
    _submitTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _frameId += 1;
      final double ts = DateTime.now().millisecondsSinceEpoch.toDouble();
      engine.submitRgbAsGrey(
        grey: _grey,
        width: 640,
        height: 640,
        frameId: _frameId,
        timestampMs: ts,
      );
    });
    _pollTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final ZyraBatch? batch = engine.pollDetections();
      if (batch != null && mounted) {
        setState(() => _latest = batch);
      }
    });
  }

  @override
  void dispose() {
    _submitTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ZyraEngine> engineAsync = ref.watch(zyraEngineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Engine Debug')),
      body: engineAsync.when(
        data: (ZyraEngine engine) {
          // Kick the loops exactly once per engine instance.
          if (_submitTimer == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _startLoops(engine);
            });
          }
          return _DebugBody(engine: engine, latest: _latest);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace s) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Engine init failed:\n$e'),
        ),
      ),
    );
  }
}

class _DebugBody extends StatelessWidget {
  const _DebugBody({required this.engine, required this.latest});

  final ZyraEngine engine;
  final ZyraBatch? latest;

  @override
  Widget build(BuildContext context) {
    final TextStyle mono = TextStyle(
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      fontFamily: 'monospace',
      color: Theme.of(context).colorScheme.onSurface,
    );
    final ZyraBatch? b = latest;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('handle=${engine.handle}', style: mono),
            Text('avgFps=${engine.avgFps.toStringAsFixed(1)}', style: mono),
            Text(
              'vulkan=${engine.vulkanActive == 1 ? "on" : engine.vulkanActive == 0 ? "cpu" : "n/a"}',
              style: mono,
            ),
            const Divider(),
            if (b == null)
              Text('no batch yet', style: mono)
            else ...<Widget>[
              Text('frameId=${b.frameId}', style: mono),
              Text(
                  'pre=${b.preprocessMs.toStringAsFixed(2)}ms '
                  'inf=${b.inferMs.toStringAsFixed(2)}ms '
                  'nms=${b.nmsMs.toStringAsFixed(2)}ms '
                  'total=${b.totalMs.toStringAsFixed(2)}ms',
                  style: mono),
              Text('rotation=${b.rotationDeg} orig=${b.origWidth}×${b.origHeight}',
                  style: mono),
              Text('vulkan=${b.vulkanActive}', style: mono),
              Text('detections=${b.detections.length}', style: mono),
              const SizedBox(height: 8),
              for (final ZyraDetection d in b.detections.take(10))
                Text(
                  '  ${kZyraClasses[d.classId]} '
                  '${d.confidence.toStringAsFixed(2)} '
                  '[${d.x1.toStringAsFixed(0)}, ${d.y1.toStringAsFixed(0)}, '
                  '${d.x2.toStringAsFixed(0)}, ${d.y2.toStringAsFixed(0)}]',
                  style: mono,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
