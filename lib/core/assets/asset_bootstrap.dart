import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Copies NCNN model assets (`yolov8n.ncnn.param` / `.bin`) out of the
/// Flutter asset bundle onto the app's support directory so NCNN can open
/// them via `fopen()`. Idempotent — re-running after first install is a
/// cheap size check.
///
/// Returns the filesystem paths for the copied model. Call once during
/// startup (main.dart) before spinning up the detector.
class AssetBootstrap {
  AssetBootstrap._();

  static const String _paramAsset = 'assets/models/yolov8n.ncnn.param';
  static const String _binAsset = 'assets/models/yolov8n.ncnn.bin';

  /// Ensure both model files exist on disk. Safe to call every launch.
  static Future<ModelPaths> ensureModelsExtracted() async {
    final Directory supportDir = await getApplicationSupportDirectory();
    final Directory modelDir =
        Directory('${supportDir.path}${Platform.pathSeparator}models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final File paramFile =
        File('${modelDir.path}${Platform.pathSeparator}yolov8n.ncnn.param');
    final File binFile =
        File('${modelDir.path}${Platform.pathSeparator}yolov8n.ncnn.bin');

    await _copyIfStale(_paramAsset, paramFile);
    await _copyIfStale(_binAsset, binFile);

    return ModelPaths(paramPath: paramFile.path, binPath: binFile.path);
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

/// Absolute filesystem paths for the extracted NCNN model.
class ModelPaths {
  const ModelPaths({required this.paramPath, required this.binPath});
  final String paramPath;
  final String binPath;
}
