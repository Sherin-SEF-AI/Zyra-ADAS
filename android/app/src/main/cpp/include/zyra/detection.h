// Phase 3 — Plain-old-data detection struct shared between the C++ engine
// and the Dart FFI layer. Kept deliberately scalar + fixed-layout so it can
// be embedded in `ZyraDetectionBatch` (Phase 4) without any marshalling.

#pragma once

#include <cstdint>

namespace zyra {

// Class ids are the canonical Zyra order mirrored in lib/core/constants.dart
// (kZyraClasses). COCO ids are mapped into this space at the tail of
// post-processing so every consumer downstream deals in Zyra ids only.
//
//   0 pedestrian
//   1 bicycle
//   2 car
//   3 motorcycle
//   4 bus
//   5 truck
//   6 auto_rickshaw   (custom models only — stock COCO YOLO never emits this)
//   7 traffic_light
//   8 traffic_sign
struct Detection {
  // Bounding box in ORIGINAL image coordinates (pre-rotation), in pixels.
  float x1;
  float y1;
  float x2;
  float y2;
  int32_t class_id;   // Zyra class id (see above)
  float confidence;   // [0, 1] — raw model score after per-class threshold gate
};

}  // namespace zyra
