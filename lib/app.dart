import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/home/home_screen.dart';
import 'ui/theme/zen_theme.dart';

class UpTimerApp extends StatelessWidget {
  const UpTimerApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ink = controller.settings.theme == 'ink';
        return MaterialApp(
          title: '成时',
          debugShowCheckedModeBanner: false,
          theme: buildZenTheme(ink: ink),
          themeAnimationDuration: const Duration(milliseconds: 460),
          themeAnimationCurve: Curves.easeInOut,
          home: HomeScreen(controller: controller),
        );
      },
    );
  }
}
