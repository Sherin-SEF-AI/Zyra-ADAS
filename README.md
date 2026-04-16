<div align="center">

# Zyra ADAS
FOR INDIAN ROADS
### Your phone is now an L2 ADAS shadow system.

**Real-time object detection + lane tracking on Android, powered by on-device NCNN inference with Vulkan acceleration. No cloud, no latency, no compromise.**

[![Android](https://img.shields.io/badge/Android-30%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://www.android.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![C++](https://img.shields.io/badge/C%2B%2B-17-00599C?style=for-the-badge&logo=cplusplus&logoColor=white)](https://isocpp.org)
[![NCNN](https://img.shields.io/badge/NCNN-Vulkan-FF6B35?style=for-the-badge)](https://github.com/Tencent/ncnn)
[![License](https://img.shields.io/badge/License-MIT-4ECDC4?style=for-the-badge)](LICENSE)

**[ What it does ](#what-it-does)** &nbsp;•&nbsp; **[ Architecture ](#architecture)** &nbsp;•&nbsp; **[ Performance ](#performance)** &nbsp;•&nbsp; **[ Quick start ](#quick-start)** &nbsp;•&nbsp; **[ Roadmap ](#roadmap)**

</div>

---

## Why Zyra ADAS

Modern cars ship L2 driver assistance that costs thousands of dollars. Most of the hard work is computer vision running on a small SoC behind the dashboard. Your phone has that same SoC. It has a camera, a GPU, GPS, accelerometers, and a screen bright enough to see in sunlight.

Zyra turns it into a **shadow-mode ADAS**: it watches the road and predicts what a real L2 system would do, side by side with what you actually do. No vehicle control, no liability, just perception that runs in your pocket.

Built for riders, fleet operators, researchers, and anyone who wants to see the world the way an autonomy stack sees it.


https://github.com/user-attachments/assets/5930e96d-a6ff-43bf-81db-19d5d245d54e



## What it does

| Capability | Detail |
|---|---|
| **YOLOv8n object detection** | Pedestrians, cyclists, cars, trucks, motorcycles, auto-rickshaws, traffic lights, traffic signs. Per class confidence thresholds calibrated against real driving footage. |
| **Classical lane tracking** | Canny + HoughLinesP + trapezoid ROI + weighted line fit. Cyan for left, yellow for right, alpha keyed to confidence so weak hypotheses fade instead of lying to the driver. |
| **Vulkan GPU inference** | NCNN with FP16 + Winograd convolutions on mobile GPUs. Automatic CPU fallback on devices without Vulkan compute. |
| **Vehicle aware** | Pick Car or Scooter at launch. Mount height, max decel, FCW TTC thresholds all flow down to the engine so alerts match the vehicle physics. |
| **Lock free hot path** | Single producer single consumer with atomic result swap. Frame drops are explicit when inference cannot keep up, never silent. |
| **Zero cloud dependency** | Every byte of inference runs on device. The app never phones home, never uploads a frame, never needs a sign in. |

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            FLUTTER UI LAYER                              │
│                                                                          │
│   VehicleSelect  ──▶  DriveScreen                                        │
│                           │                                              │
│                           ├─ CameraPreview (native SurfaceView)          │
│                           ├─ LaneOverlayPainter    (CustomPaint)         │
│                           ├─ DetectionOverlayPainter (CustomPaint)       │
│                           ├─ FpsBar       (fps, Vulkan badge, vehicle)   │
│                           └─ StatusBar    (objects, lanes, infer ms)     │
│                                                                          │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │     Riverpod AsyncNotifier
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       DART FFI BRIDGE  (zero copy)                       │
│                                                                          │
│   ZyraEngine  ──▶  DynamicLibrary.open('libzyra_perception.so')          │
│       │                                                                  │
│       ├─ submitFrame (Y, U, V pointers, strides, rotation, frame_id)     │
│       └─ pollDetections ──▶ ZyraDetectionBatch (64 dets + 8 lanes)       │
│                                                                          │
└────────────────────────────┬─────────────────────────────────────────────┘
                             │     extern "C" ABI
                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    NATIVE PERCEPTION ENGINE  (C++17)                     │
│                                                                          │
│   ┌────────────────────────┐        ┌────────────────────────┐           │
│   │  Producer  (Dart)      │        │  Consumer  (worker)    │           │
│   │                        │        │                        │           │
│   │  submit_frame ────────▶│ bound1 │─▶ Pending frame        │           │
│   │                        │ queue  │   │                    │           │
│   └────────────────────────┘        │   ▼                    │           │
│                                     │  YUV420 detect variant │           │
│                                     │   │                    │           │
│                                     │   ▼                    │           │
│                                     │  OpenCV cvtColor + resize + letterbox │
│                                     │   │                    │           │
│                     ┌───────────────┤   ▼                    │           │
│                     │               │  NCNN YOLOv8n          │           │
│                     │               │  (Vulkan or CPU)       │           │
│                     │               │   │                    │           │
│                     ▼               │   ▼                    │           │
│         HoughLaneDetector           │  Per class NMS + COCO  │           │
│         (Y plane, ROI, Canny,       │  to Zyra mapping       │           │
│          HoughLinesP, line fit)     │   │                    │           │
│                     │               │   ▼                    │           │
│                     └───────────────┼─▶ ZyraDetectionBatch   │           │
│                                     │  (dets + lanes + ms)   │           │
│                                     │   │                    │           │
│                                     └───┼────────────────────┘           │
│                                         ▼                                │
│                              mutex guarded result slot                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

   THIRD PARTY STATIC LINK :  NCNN 20250503  +  OpenCV Mobile 4.10.0
   SINGLE SHARED OBJECT    :  libzyra_perception.so  (arm64-v8a)
```

## Performance

Measured on a Realme RMX2081 (Snapdragon 662, 2020 mid range):

| Stage | Vulkan | CPU big.LITTLE |
|---|---:|---:|
| Preprocess (YUV to letterbox) | 2.1 ms | 2.1 ms |
| YOLOv8n inference | 96 ms | 180 ms |
| NMS + class map | 1.8 ms | 1.8 ms |
| Lane detect (Hough) | 4.5 ms | 4.5 ms |
| **End to end** | **~105 ms** | **~190 ms** |
| **Sustained FPS** | **10 fps** | **5 fps** |

Flagship devices (Snapdragon 8 Gen 2, Tensor G3, Dimensity 9200+) hit **30 fps Vulkan end to end** in internal profiling. Hot path is bounded by native inference, not by Dart or the Flutter framework.

## Tech stack

### On device
- **Flutter 3.41** stable, Dart 3.11, Riverpod 2.6 for reactive state
- **Camera2 YUV_420_888** stream via the Flutter camera plugin
- **dart:ffi** for the hot path (under 5 microseconds per call)
- **C++17 NDK r27c** compiled with arm64-v8a NEON
- **NCNN 20250503** with Vulkan compute, FP16 packed storage, Winograd
- **OpenCV Mobile 4.10.0** (Nihui fork, core + imgproc only, ~2 MB static)
- **YOLOv8n** converted to NCNN via pnnx, 640x640 input, 8400 anchors

### Build pipeline
- **Gradle** Android plugin with external CMake
- **CMake 3.22** with `-Wl,--gc-sections -Wl,--exclude-libs,ALL -fvisibility=hidden -O3`
- **Static OpenMP** via `-fopenmp -static-openmp` so the APK ships no runtime `.so`
- **pnnx** for ONNX to NCNN conversion

## Quick start

### Prerequisites

- Flutter 3.41 stable
- Android SDK with NDK r27c (`27.2.12479018`)
- CMake 3.22 (Android-Gradle bundled)
- A physical Android device with Android 11+ (API 30)

### Build

```bash
git clone https://github.com/Sherin-SEF-AI/Zyra-ADAS.git
cd Zyra-ADAS

# Fetch third_party statics (NCNN + OpenCV Mobile) into
#   android/app/src/main/cpp/third_party/{ncnn-android,opencv-mobile}/arm64-v8a/
# See assets/models/README for model conversion steps.

flutter pub get
flutter build apk --debug --target-platform=android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Run

Open the app, pick **Car** or **Scooter**, grant camera permission, mount the phone on your dashboard. Bounding boxes appear within two frames of the stream starting. Lane overlay kicks in as soon as Canny has enough gradient to hit the Hough threshold.

## Project layout

```
ZyraADAS/
├── lib/                             # Dart / Flutter
│   ├── app/                         # Theme, routes
│   ├── core/
│   │   ├── constants.dart           # Zyra class map, colors
│   │   ├── ffi/                     # dart:ffi bindings to libzyra
│   │   └── permissions/             # Runtime permission flow
│   └── features/
│       ├── vehicle_select/          # Profile picker + persistence
│       └── drive/                   # Camera + overlays + HUD
│
├── android/app/src/main/cpp/        # Native engine
│   ├── CMakeLists.txt
│   ├── include/zyra/                # FFI ABI, detector, engine, lane
│   ├── src/
│   │   ├── detector.cpp             # NCNN YOLOv8n wrapper
│   │   ├── preprocess.cpp           # YUV variants + letterbox
│   │   ├── nms.cpp                  # Per class NMS + COCO to Zyra
│   │   ├── lane.cpp                 # Hough lane detector
│   │   ├── engine.cpp               # Producer / consumer worker
│   │   └── ffi_api.cpp              # extern "C" surface
│   └── third_party/                 # NCNN + OpenCV Mobile prebuilts
│
└── assets/models/                   # yolov8n.ncnn.param + .bin
```

## Roadmap

| Phase | Status | Delivers |
|---|---|---|
| 0. Toolchain pin | done | Flutter 3.41, NDK r27c, NCNN 20250503, OpenCV 4.10 |
| 1. Flutter scaffold | done | Dark theme, vehicle select, persistence |
| 2. C++ NDK bootstrap | done | libzyra_perception.so, CMake wiring, FFI stub |
| 3. YOLOv8 detector | done | NCNN Vulkan + CPU, per class NMS, selftest |
| 4. dart:ffi bridge | done | Producer consumer, batch struct, Riverpod provider |
| 5. Live overlay | done | Camera preview + bbox overlay + FPS HUD |
| 6. Lane tracking | done | Classical Hough pipeline, per side colors |
| 7. Vehicle dynamics | planned | IMU + GPS fusion, ego kinematics |
| 8. Shadow comparator | planned | Predicted L2 action vs driver action, logged per trip |
| 9. FCW + LDW alerts | planned | Audio + haptic, calibrated per vehicle profile |
| 10. Trip recorder | planned | Offline session export, ride quality score |

## Design decisions

- **Single shared object.** NCNN, OpenCV, and our glue all static link into `libzyra_perception.so`. Dart sees one clean ABI surface, the APK has one `.so`, symbol visibility is `hidden` by default so nothing leaks.
- **dart:ffi over MethodChannel.** MethodChannel serializes JSON and hops thread boundaries, costs around 1 to 2 ms per call. At 30 fps that is measurable. FFI is under 5 microseconds.
- **C++ owns the whole hot path.** YUV to RGB, letterbox, inference, NMS, class map, and lane detection all happen native. Dart only produces frame buffers and consumes result batches.
- **Bounded queue, drop on overrun.** Realtime contract: if inference is behind, the older frame is discarded. No buffering, no latency creep. This matches how real ADAS stacks schedule.
- **Offline model conversion.** ONNX to NCNN happens once on the developer machine via pnnx. Runtime loads pre-converted `.param` + `.bin` directly.
- **Static OpenMP.** Link with `-static-openmp` so NCNN and OpenCV resolve `__kmpc_*` symbols without shipping `libomp.so` in the APK.

## Hardware requirements

**Minimum**
- Android 11 (API 30)
- arm64-v8a
- 4 GB RAM
- Any rear camera supporting YUV_420_888

**Recommended**
- Android 13+
- Vulkan 1.1 compute capable GPU (Adreno 640+, Mali G76+, Xclipse)
- 6 GB+ RAM
- OIS rear camera
- Dashboard mount with clear forward view

## Contributing

Zyra ADAS is research hardware software. If you run it on your own car or scooter, I want to hear about it. Open a GitHub issue with your vehicle, device, and a short clip of the overlay.

Pull requests welcome for:
- Additional vehicle profiles
- Alternative lane detectors (deep learning swap-in)
- iOS port (needs CameraX replacement)
- Trip recorder / replay tooling

## License

MIT. See [LICENSE](LICENSE).

## Author

**Sherin Joseph Roy**

Builder, researcher, and independent engineer working on computer vision, robotics, and driver assistance. Zyra ADAS is part of a broader research program on phone native autonomy.

- GitHub: [@Sherin-SEF-AI](https://github.com/Sherin-SEF-AI)
- Contact for collaboration: open an issue on this repo.

## Acknowledgements

- **Tencent NCNN** team for the best mobile inference runtime on the planet.
- **Nihui** for OpenCV Mobile, proving you can strip a 40 MB SDK down to 2 MB without losing what matters.
- **Ultralytics** for YOLOv8 and the letterbox preprocessing pattern that everyone now copies.
- The **pnnx** project for making ONNX to NCNN painless.

---

<div align="center">

**If Zyra ADAS runs on your phone, star the repo. If it runs on your dashboard, tell me what you see.**

</div>
