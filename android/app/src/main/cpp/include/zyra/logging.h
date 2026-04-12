#pragma once

// Lightweight logcat wrappers. All runtime logging in the engine goes through
// these so the tag ("Zyra") is consistent and easy to `adb logcat -s Zyra:*`.

#include <android/log.h>

#define ZYRA_LOG_TAG "Zyra"

#define ZYRA_LOGI(...) \
  ((void)__android_log_print(ANDROID_LOG_INFO, ZYRA_LOG_TAG, __VA_ARGS__))
#define ZYRA_LOGW(...) \
  ((void)__android_log_print(ANDROID_LOG_WARN, ZYRA_LOG_TAG, __VA_ARGS__))
#define ZYRA_LOGE(...) \
  ((void)__android_log_print(ANDROID_LOG_ERROR, ZYRA_LOG_TAG, __VA_ARGS__))
#define ZYRA_LOGD(...) \
  ((void)__android_log_print(ANDROID_LOG_DEBUG, ZYRA_LOG_TAG, __VA_ARGS__))

namespace zyra {

// Emit a one-line banner identifying the native library build: NCNN version,
// OpenCV build info, ABI. Called once from Dart at engine-bootstrap time to
// prove the .so loaded and linked against the expected third-party versions.
void log_version_banner();

}  // namespace zyra
