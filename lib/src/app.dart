import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'features/workspace/presentation/screens/workspace_screen.dart';

class ClarixApp extends StatelessWidget {
  const ClarixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: ShadApp(
        debugShowCheckedModeBanner: false,
        title: 'Clarix',
        themeMode: ThemeMode.dark,
        theme: _buildTheme(),
        darkTheme: _buildTheme(),
        home: const _WindowBootstrap(child: WorkspaceScreen()),
      ),
    );
  }

  ShadThemeData _buildTheme() {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
      textTheme: ShadTextTheme.fromGoogleFont(GoogleFonts.instrumentSans),
    );
  }
}

class _WindowBootstrap extends StatefulWidget {
  const _WindowBootstrap({required this.child});

  final Widget child;

  @override
  State<_WindowBootstrap> createState() => _WindowBootstrapState();
}

class _WindowBootstrapState extends State<_WindowBootstrap> {
  @override
  void initState() {
    super.initState();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1500, 940),
        minimumSize: Size(1100, 760),
        center: true,
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
