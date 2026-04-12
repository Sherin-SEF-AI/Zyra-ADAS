// Phase 3 — Per-class non-max suppression with small-object handling.
// Mirrors YOLODetector._nms + ._nms_core in the desktop reference file:
// /home/netcom/Desktop/Zyra-Perception/zyra/detection/yolo_trt.py
// (see _SMALL_OBJ_AREA and _SMALL_OBJ_NMS_IOU constants there).

#pragma once

#include <vector>

#include "zyra/detection.h"

namespace zyra::internal {

// Area threshold below which a box is considered "small" and gets NMSed at
// a reduced IoU to avoid merging distant pedestrians / poles. Same value
// as the desktop reference — do NOT retune without also retuning there.
constexpr float kSmallObjectAreaPx = 1000.0f;
constexpr float kSmallObjectNmsIou = 0.30f;

// Per-class NMS. When *both* small and large objects are present for a
// given class they are NMSed separately (small → 0.30, large → `iou_large`);
// when only small objects are present, the small-object IoU is used; when
// only large, `iou_large` is used. Returns the surviving detections in
// descending confidence order.
std::vector<Detection> per_class_nms(const std::vector<Detection>& dets,
                                     float iou_large);

}  // namespace zyra::internal
