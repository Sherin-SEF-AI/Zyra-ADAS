/// Project-wide constants that mirror the desktop Zyra reference system.
///
/// Everything here is intentionally duplicated on the C++ side (see
/// `android/app/src/main/cpp/src/nms.cpp` in Phase 3) so Dart and C++ agree on
/// class ids and thresholds without a runtime registry.

library;

/// Canonical Zyra class list — index into this list IS the Zyra class id.
///
/// Order matches the desktop system's post-mapping class table. Keep stable;
/// the C POD `ZyraDetection.class_id` refers to this index.
const List<String> kZyraClasses = <String>[
  'pedestrian', // 0
  'bicycle', // 1
  'car', // 2
  'motorcycle', // 3
  'bus', // 4
  'truck', // 5
  'auto_rickshaw', // 6
  'traffic_light', // 7
  'traffic_sign', // 8
];

/// Reverse lookup: class name → Zyra id.
final Map<String, int> kZyraClassToId = <String, int>{
  for (int i = 0; i < kZyraClasses.length; i++) kZyraClasses[i]: i,
};

/// COCO id → Zyra class name.
///
/// Copied from `/home/netcom/Desktop/Zyra-Perception/zyra/detection/yolo_trt.py`
/// — single source of truth for what each COCO id means to us. Entries not
/// present here are dropped during post-processing.
const Map<int, String> kCocoIdToZyra = <int, String>{
  0: 'pedestrian', // COCO "person"
  1: 'bicycle',
  2: 'car',
  3: 'motorcycle',
  5: 'bus',
  7: 'truck',
  9: 'traffic_light',
  11: 'traffic_sign', // COCO "stop sign" — Zyra treats all signs as one class
};

/// Per-class confidence thresholds. A detection is kept only if its score
/// exceeds both the global threshold AND this class-specific threshold.
///
/// Copied from desktop `DEFAULT_CLASS_THRESHOLDS`.
const Map<String, double> kClassThresholds = <String, double>{
  'pedestrian': 0.15, // aggressive recall — missing a pedestrian is expensive
  'bicycle': 0.18,    // small/distant bikes must not be missed
  'motorcycle': 0.20,
  'auto_rickshaw': 0.22,
  'car': 0.30,
  'truck': 0.30,
  'bus': 0.30,
  'traffic_light': 0.35,
  'traffic_sign': 0.35,
};

/// Global fallback threshold if a class is missing from [kClassThresholds].
const double kGlobalConfThreshold = 0.25;

/// Default NMS IoU. Matches Ultralytics reference.
const double kDefaultNmsIou = 0.45;

/// Max detections per frame — matches fixed buffer in [ZyraDetectionBatch]
/// (defined in C POD struct). Tune only together with the C header.
const int kMaxDetectionsPerFrame = 64;

/// Phase 10 — assumed horizontal FoV for the back camera, in degrees.
///
/// The Flutter `camera` plugin does not expose intrinsics, and the
/// resolution it picks may not match the sensor's full FoV. Most modern
/// Android phones' main rear cameras span ~66–72° horizontal FoV at
/// their default (non-ultrawide) output — 68° is a reasonable midpoint
/// that keeps range estimates within ~10% accuracy at typical FCW
/// distances without introducing a manual calibration UX.
const double kDefaultHfovDeg = 68.0;
