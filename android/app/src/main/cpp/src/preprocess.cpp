// Phase 3 — YUV_420_888 → RGB conversion + YOLO letterbox.
//
// Android camera frames arrive in one of three layouts:
//   * NV21 (semi-planar, V first): uv_pixel_stride == 2, v_ptr < u_ptr
//   * NV12 (semi-planar, U first): uv_pixel_stride == 2, u_ptr < v_ptr
//   * I420 (planar):               uv_pixel_stride == 1
// We detect the variant from the plane pointers + pixel stride on each call
// (devices don't switch mid-session, but the cost is one pointer compare).

#include "zyra/internal/preprocess.h"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <cmath>
#include <vector>

#include <opencv2/imgproc.hpp>

namespace zyra::internal {

namespace {

// Copy Y plane into a contiguous (width × height) buffer, stripping any
// row-stride padding. Returned by value via out-parameter to avoid an
// extra allocation inside the caller.
void copy_y_plane(const FrameView& f, uint8_t* dst) {
  if (f.y_row_stride == f.width) {
    std::memcpy(dst, f.y, static_cast<size_t>(f.width) * f.height);
    return;
  }
  for (int r = 0; r < f.height; ++r) {
    std::memcpy(dst + static_cast<size_t>(r) * f.width,
                f.y + static_cast<size_t>(r) * f.y_row_stride,
                static_cast<size_t>(f.width));
  }
}

}  // namespace

cv::Mat yuv420_to_rgb(const FrameView& f) {
  const int W = f.width;
  const int H = f.height;
  cv::Mat rgb;

  if (f.uv_pixel_stride == 2) {
    // NV21 / NV12 — semiplanar. Materialise into a (H*3/2, W, 1) buffer so
    // OpenCV's fast-path cvtColor kernels can be used unmodified.
    std::vector<uint8_t> buf(static_cast<size_t>(W) * H * 3 / 2);
    copy_y_plane(f, buf.data());

    // Pick the lower-addressed interleaved plane start (NV21 → V first,
    // NV12 → U first). Each row contains W bytes (W/2 pairs × 2 bytes).
    const bool is_nv21 = (f.v < f.u);
    const uint8_t* uv_src = is_nv21 ? f.v : f.u;
    uint8_t* uv_dst = buf.data() + static_cast<size_t>(W) * H;

    const int uv_rows = H / 2;
    if (f.uv_row_stride == W) {
      std::memcpy(uv_dst, uv_src, static_cast<size_t>(W) * uv_rows);
    } else {
      for (int r = 0; r < uv_rows; ++r) {
        std::memcpy(uv_dst + static_cast<size_t>(r) * W,
                    uv_src + static_cast<size_t>(r) * f.uv_row_stride,
                    static_cast<size_t>(W));
      }
    }

    cv::Mat yuv(H * 3 / 2, W, CV_8UC1, buf.data());
    cv::cvtColor(yuv, rgb,
                 is_nv21 ? cv::COLOR_YUV2RGB_NV21 : cv::COLOR_YUV2RGB_NV12);
  } else {
    // I420 — fully planar. Same trick: pack into YUV I420 layout then let
    // OpenCV do the colorspace math.
    std::vector<uint8_t> buf(static_cast<size_t>(W) * H * 3 / 2);
    copy_y_plane(f, buf.data());

    uint8_t* u_dst = buf.data() + static_cast<size_t>(W) * H;
    uint8_t* v_dst = u_dst + static_cast<size_t>(W) * H / 4;
    const int uv_rows = H / 2;
    const int uv_cols = W / 2;

    for (int r = 0; r < uv_rows; ++r) {
      std::memcpy(u_dst + static_cast<size_t>(r) * uv_cols,
                  f.u + static_cast<size_t>(r) * f.uv_row_stride,
                  static_cast<size_t>(uv_cols));
      std::memcpy(v_dst + static_cast<size_t>(r) * uv_cols,
                  f.v + static_cast<size_t>(r) * f.uv_row_stride,
                  static_cast<size_t>(uv_cols));
    }

    cv::Mat yuv(H * 3 / 2, W, CV_8UC1, buf.data());
    cv::cvtColor(yuv, rgb, cv::COLOR_YUV2RGB_I420);
  }

  return rgb;
}

cv::Mat letterbox_rgb(const cv::Mat& rgb_in, int target, LetterboxMeta& meta) {
  const int W = rgb_in.cols;
  const int H = rgb_in.rows;
  const float scale =
      std::min(static_cast<float>(target) / static_cast<float>(W),
               static_cast<float>(target) / static_cast<float>(H));
  const int new_w = static_cast<int>(std::lround(W * scale));
  const int new_h = static_cast<int>(std::lround(H * scale));

  cv::Mat resized;
  cv::resize(rgb_in, resized, cv::Size(new_w, new_h), 0, 0, cv::INTER_LINEAR);

  const int pad_x = (target - new_w) / 2;
  const int pad_y = (target - new_h) / 2;

  // Scalar(114, 114, 114) — matches Ultralytics + desktop `letterbox()`.
  cv::Mat padded(target, target, CV_8UC3, cv::Scalar(114, 114, 114));
  resized.copyTo(padded(cv::Rect(pad_x, pad_y, new_w, new_h)));

  meta.scale = scale;
  meta.pad_x = pad_x;
  meta.pad_y = pad_y;
  meta.orig_w = W;
  meta.orig_h = H;
  return padded;
}

}  // namespace zyra::internal
