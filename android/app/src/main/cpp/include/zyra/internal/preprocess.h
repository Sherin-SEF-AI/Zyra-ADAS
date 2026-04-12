// Phase 3 — Internal preprocessing helpers. Not part of the FFI surface.
// Kept in a separate header so we can unit-test them in isolation later.

#pragma once

#include <opencv2/core.hpp>

#include "zyra/frame.h"

namespace zyra::internal {

// Metadata describing a letterbox transform, used to map detection boxes
// from letterbox coordinate space back to the original image coordinate
// space. Mirrors `letterbox()` + `_scale_boxes_to_original()` in
// /home/netcom/Desktop/Zyra-Perception/zyra/detection/yolo_trt.py so the
// mobile port produces bit-identical boxes on the same input.
struct LetterboxMeta {
  float scale = 1.0f;
  int pad_x = 0;
  int pad_y = 0;
  int orig_w = 0;
  int orig_h = 0;
};

// Convert a YUV_420_888 Android camera frame to a contiguous RGB888
// cv::Mat (h × w × 3, CV_8UC3). Handles NV21 / NV12 / I420 by inspecting
// the plane pixel/row strides on the hot path — Android devices ship with
// any of the three in practice.
cv::Mat yuv420_to_rgb(const FrameView& frame);

// Letterbox an RGB image to target × target, filling the padding with
// (114, 114, 114) and storing the transform metadata so we can unwind it
// post-inference. Matches Ultralytics / desktop Zyra letterbox exactly.
cv::Mat letterbox_rgb(const cv::Mat& rgb_in, int target, LetterboxMeta& meta);

// Undo letterbox + clip to image bounds, in-place on a single box.
inline void unletterbox_box(float& x1, float& y1, float& x2, float& y2,
                            const LetterboxMeta& m) {
  x1 = (x1 - static_cast<float>(m.pad_x)) / m.scale;
  y1 = (y1 - static_cast<float>(m.pad_y)) / m.scale;
  x2 = (x2 - static_cast<float>(m.pad_x)) / m.scale;
  y2 = (y2 - static_cast<float>(m.pad_y)) / m.scale;
  const float ow = static_cast<float>(m.orig_w);
  const float oh = static_cast<float>(m.orig_h);
  if (x1 < 0.0f) x1 = 0.0f; else if (x1 > ow) x1 = ow;
  if (x2 < 0.0f) x2 = 0.0f; else if (x2 > ow) x2 = ow;
  if (y1 < 0.0f) y1 = 0.0f; else if (y1 > oh) y1 = oh;
  if (y2 < 0.0f) y2 = 0.0f; else if (y2 > oh) y2 = oh;
}

}  // namespace zyra::internal
