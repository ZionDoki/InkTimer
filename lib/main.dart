import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/repository.dart';
import 'data/store_bootstrap.dart';
import 'services/runtime_effects.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  } on Object {
    // 桌面或 Web 不支持系统栏控制时无须处理。
  }

  final storage = await initializeKeyValueStore();
  final controller = AppController(
    repository: Repository(storage.store),
    effects: FlutterRuntimeEffects(),
    startupNotice: storage.notice,
  );
  await controller.initialize();
  runApp(InkTimerApp(controller: controller));
}
