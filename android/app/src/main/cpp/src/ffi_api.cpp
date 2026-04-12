// Phase 2 FFI stub. This file is intentionally tiny — the full detection API
// arrives in Phase 4. Right now all we want is proof that:
//   (a) the C++ toolchain compiles against NCNN + OpenCV headers,
//   (b) the linker resolves NCNN + OpenCV static libs,
//   (c) the resulting .so loads inside the Android app process,
//   (d) Dart can call into it via FFI.

#include "zyra/ffi_api.h"

#include <ncnn/platform.h>

#include "zyra/logging.h"

extern "C" {

ZYRA_API int32_t zyra_hello(void) {
  return 42;
}

ZYRA_API void zyra_log_version(void) {
  zyra::log_version_banner();
}

ZYRA_API const char* zyra_ncnn_version(void) {
  return NCNN_VERSION_STRING;
}

}  // extern "C"
