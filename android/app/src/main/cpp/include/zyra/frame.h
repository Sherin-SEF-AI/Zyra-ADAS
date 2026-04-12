// Phase 3 — Non-owning view over an Android YUV_420_888 frame.
//
// The Dart side (Phase 4) obtains `CameraImage` plane pointers and passes
// them directly in. We never copy the input buffers in the FFI layer —
// preprocess.cpp materialises a contiguous YUV buffer locally and hands it
// to OpenCV / NCNN.

#pragma once

#include <cstdint>

namespace zyra {

struct FrameView {
  const uint8_t* y;
  const uint8_t* u;
  const uint8_t* v;
  int32_t width;             // luma plane width  (pixels)
  int32_t height;            // luma plane height (pixels)
  int32_t y_row_stride;      // bytes per row of Y plane (≥ width)
  int32_t uv_row_stride;     // bytes per row of U/V plane
  int32_t uv_pixel_stride;   // 1 = I420 (planar), 2 = NV12 / NV21 (semi-planar)
  int32_t rotation_deg;      // 0, 90, 180, 270 — sensor→display rotation
};

}  // namespace zyra
