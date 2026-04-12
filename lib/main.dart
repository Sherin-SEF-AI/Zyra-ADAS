import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/routes.dart';
import 'app/theme.dart';
import 'core/ffi/zyra_native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 2 smoke test — prove libzyra_perception.so loads, NCNN + OpenCV
  // are linked in, and Dart→C++ FFI is callable end-to-end. Logs on both
  // sides so we can verify via `adb logcat -s Zyra:V flutter:V` that the
  // values agree.
  try {
    final ZyraNative native = ZyraNative.open();
    final int hello = native.hello();
    native.logVersion();
    debugPrint(
        '[Zyra] FFI bootstrap ok — zyra_hello=$hello ncnn=${native.ncnnVersion()}');
  } catch (e, st) {
    debugPrint('[Zyra] FFI bootstrap FAILED: $e\n$st');
  }

  // Lock the app to portrait — driver-facing HUD is designed for portrait only.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // Immersive-lite: keep system bars translucent so the camera preview can
  // extend edge-to-edge in later phases.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: ZyraApp()));
}

class ZyraApp extends StatelessWidget {
  const ZyraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zyra Mobile',
      debugShowCheckedModeBanner: false,
      theme: ZyraTheme.dark(),
      themeMode: ThemeMode.dark,
      initialRoute: ZyraRoutes.root,
      onGenerateRoute: ZyraRoutes.onGenerateRoute,
    );
  }
}
