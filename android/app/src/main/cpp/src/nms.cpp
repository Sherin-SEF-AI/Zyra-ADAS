// Phase 3 — Per-class NMS with small-object split. See also:
//   /home/netcom/Desktop/Zyra-Perception/zyra/detection/yolo_trt.py
// — this is a straight port of `YOLODetector._nms` / `._nms_core`.
//
// Both sides must stay in sync: the shadow comparator (Phase 8+) will
// compare mobile output against desktop output on the same recorded
// session, and any divergence here becomes noise in the metric.

#include "zyra/internal/nms.h"

#include <algorithm>
#include <cstddef>
#include <unordered_map>
#include <vector>

namespace zyra::internal {

namespace {

inline float box_area(const Detection& d) {
  const float w = d.x2 - d.x1;
  const float h = d.y2 - d.y1;
  return (w > 0.0f && h > 0.0f) ? w * h : 0.0f;
}

inline float box_iou(const Detection& a, const Detection& b) {
  const float ix1 = std::max(a.x1, b.x1);
  const float iy1 = std::max(a.y1, b.y1);
  const float ix2 = std::min(a.x2, b.x2);
  const float iy2 = std::min(a.y2, b.y2);
  const float iw = ix2 - ix1;
  const float ih = iy2 - iy1;
  if (iw <= 0.0f || ih <= 0.0f) return 0.0f;
  const float inter = iw * ih;
  const float uni = box_area(a) + box_area(b) - inter;
  return uni > 0.0f ? inter / uni : 0.0f;
}

// Classical greedy NMS over the subset indexed by `idx`. Appends kept
// indices into `kept` in descending confidence order.
void greedy_nms(const std::vector<Detection>& dets,
                std::vector<size_t>& idx,
                float iou_thresh,
                std::vector<size_t>& kept) {
  std::sort(idx.begin(), idx.end(),
            [&dets](size_t a, size_t b) {
              return dets[a].confidence > dets[b].confidence;
            });
  std::vector<char> suppressed(idx.size(), 0);
  for (size_t i = 0; i < idx.size(); ++i) {
    if (suppressed[i]) continue;
    kept.push_back(idx[i]);
    for (size_t j = i + 1; j < idx.size(); ++j) {
      if (suppressed[j]) continue;
      if (box_iou(dets[idx[i]], dets[idx[j]]) > iou_thresh) {
        suppressed[j] = 1;
      }
    }
  }
}

}  // namespace

std::vector<Detection> per_class_nms(const std::vector<Detection>& dets,
                                     float iou_large) {
  if (dets.empty()) return {};

  // Group indices by Zyra class id. Classes are <= 10; skipping the
  // reserve hint keeps this header free of detector.h.
  std::unordered_map<int, std::vector<size_t>> by_class;
  for (size_t i = 0; i < dets.size(); ++i) {
    by_class[dets[i].class_id].push_back(i);
  }

  std::vector<size_t> survivors;
  survivors.reserve(dets.size());

  for (auto& kv : by_class) {
    auto& group = kv.second;

    std::vector<size_t> small;
    std::vector<size_t> large;
    small.reserve(group.size());
    large.reserve(group.size());
    for (size_t i : group) {
      if (box_area(dets[i]) < kSmallObjectAreaPx) {
        small.push_back(i);
      } else {
        large.push_back(i);
      }
    }

    const bool has_small = !small.empty();
    const bool has_large = !large.empty();
    if (has_small && has_large) {
      greedy_nms(dets, small, kSmallObjectNmsIou, survivors);
      greedy_nms(dets, large, iou_large, survivors);
    } else if (has_small) {
      // Only small objects in this class → use the reduced IoU. Matches
      // desktop behaviour where `effective_iou = _SMALL_OBJ_NMS_IOU`.
      greedy_nms(dets, small, kSmallObjectNmsIou, survivors);
    } else {
      greedy_nms(dets, large, iou_large, survivors);
    }
  }

  // Materialise survivors in descending confidence order.
  std::sort(survivors.begin(), survivors.end(),
            [&dets](size_t a, size_t b) {
              return dets[a].confidence > dets[b].confidence;
            });

  std::vector<Detection> out;
  out.reserve(survivors.size());
  for (size_t i : survivors) out.push_back(dets[i]);
  return out;
}

}  // namespace zyra::internal
