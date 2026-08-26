import 'dart:io';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
import 'workspace_common.dart';

class DesktopWindowChrome extends ConsumerWidget {
  const DesktopWindowChrome({
    required this.child,
    required this.onImport,
    required this.onOpenSettings,
    required this.onSearch,
    this.onSave,
    this.showDocumentActions = false,
    this.useNativeWindowControls = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onImport;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onSearch;
  final VoidCallback? onSave;
  final bool showDocumentActions;
  final bool useNativeWindowControls;

  static const double _titleBarHeight = 56;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Column(
        children: <Widget>[
          Container(
            key: const Key('desktop-window-chrome'),
            height: _titleBarHeight,
            color: colors.canvas,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 24),
                if (showDocumentActions)
                  IconButton(
                    key: const Key('chrome-save'),
                    tooltip: 'Save PDF (Ctrl+S)',
                    onPressed: onSave,
                    icon: Icon(Icons.save_outlined, color: colors.textMuted),
                  ),
                Expanded(
                  child: _SearchShell(
                    onImport: onImport,
                    onSearch: onSearch,
                    colors: colors,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: useNativeWindowControls
                      ? MoveWindow()
                      : const SizedBox(),
                ),
                IconButton(
                  key: const Key('chrome-overflow'),
                  tooltip: 'More',
                  onPressed: () {},
                  icon: Icon(Icons.more_horiz, color: colors.textMuted),
                ),
                PopupMenuButton<String>(
                  key: const Key('chrome-menu'),
                  tooltip: 'Menu',
                  color: colors.panelRaised,
                  onSelected: (_) => onOpenSettings(),
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                      ],
                  icon: Icon(Icons.menu, color: colors.textMuted),
                ),
                if (useNativeWindowControls &&
                    !Platform.environment.containsKey(
                      'FLUTTER_TEST',
                    )) ...<Widget>[
                  MinimizeWindowButton(
                    key: const Key('chrome-minimize'),
                    colors: _buttonColors(colors),
                  ),
                  MaximizeWindowButton(
                    key: const Key('chrome-maximize'),
                    colors: _buttonColors(colors),
                  ),
                  CloseWindowButton(
                    key: const Key('chrome-close'),
                    colors: _closeColors(colors),
                  ),
                ] else ...<Widget>[
                  const SizedBox(key: Key('chrome-minimize'), width: 46),
                  const SizedBox(key: Key('chrome-maximize'), width: 46),
                  const SizedBox(key: Key('chrome-close'), width: 46),
                ],
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  static WindowButtonColors _buttonColors(WorkspaceSurfaceTokens colors) =>
      WindowButtonColors(
        iconNormal: colors.textStrong,
        mouseOver: colors.accentSoft,
        iconMouseOver: colors.textStrong,
      );
  static WindowButtonColors _closeColors(WorkspaceSurfaceTokens colors) =>
      WindowButtonColors(
        iconNormal: colors.textStrong,
        mouseOver: const Color(0xFF87332B),
        iconMouseOver: colors.textStrong,
      );
}

class _SearchShell extends StatelessWidget {
  const _SearchShell({
    required this.onImport,
    required this.onSearch,
    required this.colors,
  });
  final VoidCallback onImport;
  final ValueChanged<String> onSearch;
  final WorkspaceSurfaceTokens colors;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('chrome-search-field'),
    height: 36,
    padding: const EdgeInsets.only(left: 14),
    decoration: BoxDecoration(
      color: colors.panelRaised,
      border: Border.all(color: colors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: <Widget>[
        Icon(Icons.search, color: colors.textMuted),
        const SizedBox(width: 14),
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: TextField(
              onSubmitted: onSearch,
              style: GoogleFonts.roboto(color: colors.textStrong, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search PDFs…',
                hintStyle: GoogleFonts.roboto(
                  color: colors.textMuted,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ),
        SizedBox(height: 20, child: VerticalDivider(color: colors.border)),
        IconButton(
          key: const Key('chrome-import'),
          onPressed: onImport,
          icon: Icon(Icons.add, color: colors.textMuted),
        ),
        IconButton(
          key: const Key('chrome-scan-import'),
          onPressed: onImport,
          icon: Icon(Icons.center_focus_strong, color: colors.textMuted),
        ),
      ],
    ),
  );
}
