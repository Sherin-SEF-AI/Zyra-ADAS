#include "zyra/logging.h"

#include <ncnn/platform.h>  // NCNN_VERSION_STRING
#include <opencv2/core/version.hpp>

namespace zyra {

void log_version_banner() {
#if defined(__aarch64__)
  constexpr const char* kAbi = "arm64-v8a";
#elif defined(__x86_64__)
  constexpr const char* kAbi = "x86_64";
#else
  constexpr const char* kAbi = "unknown";
#endif

  ZYRA_LOGI(
      "libzyra_perception loaded — ncnn=%s  opencv=%d.%d.%d  abi=%s",
      NCNN_VERSION_STRING, CV_MAJOR_VERSION, CV_MINOR_VERSION,
      CV_SUBMINOR_VERSION, kAbi);
}

}  // namespace zyra
