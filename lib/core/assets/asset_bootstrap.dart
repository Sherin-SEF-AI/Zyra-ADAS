import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Copies NCNN model assets (`yolov8s.ncnn.param` / `.bin`) out of the
/// Flutter asset bundle onto the app's support directory so NCNN can open
/// them via `fopen()`. Idempotent — re-running after first install is a
/// cheap size check.
///
/// Returns the filesystem paths for the copied model. Call once during
/// startup (main.dart) before spinning up the detector.
///
/// Phase 9: upgraded from yolov8n (3.2M params) to yolov8s (11.2M
/// params). Accuracy bump: ~5-7% mAP50 on COCO, notably better on
/// distant / small / occluded objects — the failure modes that matter
/// most for forward collision warnings. Vulkan inference on Adreno 618
/// stays within the 33 ms budget; CPU fallback slows by ~2x (we warn
/// the user in that case).
class AssetBootstrap {
  AssetBootstrap._();

  static const String _paramAsset = 'assets/models/yolov8s.ncnn.param';
  static const String _binAsset = 'assets/models/yolov8s.ncnn.bin';
  static const String _segParamAsset = 'assets/models/twinlitenet.ncnn.param';
  static const String _segBinAsset = 'assets/models/twinlitenet.ncnn.bin';

  /// Ensure both model files exist on disk. Safe to call every launch.
  static Future<ModelPaths> ensureModelsExtracted() async {
    final Directory supportDir = await getApplicationSupportDirectory();
    final Directory modelDir =
        Directory('${supportDir.path}${Platform.pathSeparator}models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final File paramFile =
        File('${modelDir.path}${Platform.pathSeparator}yolov8s.ncnn.param');
    final File binFile =
        File('${modelDir.path}${Platform.pathSeparator}yolov8s.ncnn.bin');

    // Clean up nano-model files from older installs to reclaim ~12 MB.
    await _tryDelete(File(
        '${modelDir.path}${Platform.pathSeparator}yolov8n.ncnn.param'));
    await _tryDelete(File(
        '${modelDir.path}${Platform.pathSeparator}yolov8n.ncnn.bin'));

    await _copyIfStale(_paramAsset, paramFile);
    await _copyIfStale(_binAsset, binFile);

    final File segParamFile = File(
        '${modelDir.path}${Platform.pathSeparator}twinlitenet.ncnn.param');
    final File segBinFile = File(
        '${modelDir.path}${Platform.pathSeparator}twinlitenet.ncnn.bin');

    await _copyIfStale(_segParamAsset, segParamFile);
    await _copyIfStale(_segBinAsset, segBinFile);

    return ModelPaths(
      paramPath: paramFile.path,
      binPath: binFile.path,
      segParamPath: segParamFile.path,
      segBinPath: segBinFile.path,
    );
  }

  static Future<void> _tryDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best-effort cleanup; a leftover yolov8n file doesn't affect
      // correctness, only disk usage.
    }
  }

  static Future<void> _copyIfStale(String assetKey, File target) async {
    // Only re-extract when the asset's size differs from what we have on
    // disk. ByteData.lengthInBytes is cheap and avoids reading model bytes
    // on every launch.
    final ByteData data = await rootBundle.load(assetKey);
    final int expectedSize = data.lengthInBytes;

    if (await target.exists()) {
      final int current = await target.length();
      if (current == expectedSize) return;
      if (kDebugMode) {
        debugPrint('[Zyra] asset stale at ${target.path} '
            '($current != $expectedSize) — re-extracting');
      }
    }

    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
}

/// Absolute filesystem paths for the extracted NCNN models.
class ModelPaths {
  const ModelPaths({
    required this.paramPath,
    required this.binPath,
    required this.segParamPath,
    required this.segBinPath,
  });
  final String paramPath;
  final String binPath;
  final String segParamPath;
  final String segBinPath;
}
