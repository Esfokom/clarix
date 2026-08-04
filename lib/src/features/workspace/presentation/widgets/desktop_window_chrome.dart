import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DesktopWindowChrome extends StatelessWidget {
  const DesktopWindowChrome({
    required this.child,
    required this.onImport,
    required this.onOpenSettings,
    this.useNativeWindowControls = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onImport;
  final VoidCallback onOpenSettings;
  final bool useNativeWindowControls;

  static const Color _chrome = Color(0xFF2F2F2F);
  static const Color _search = Color(0xFF3A3A3A);
  static const Color _muted = Color(0xFFA6A6A6);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Column(
        children: <Widget>[
          _titleBar(
            Container(
              key: const Key('desktop-window-chrome'),
              height: 48,
              color: _chrome,
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 30),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 660),
                        child: _SearchShell(onImport: onImport),
                      ),
                    ),
                  ),
                  Expanded(
                    child: useNativeWindowControls
                        ? MoveWindow()
                        : const SizedBox(),
                  ),
                  IconButton(
                    key: const Key('chrome-overflow'),
                    tooltip: 'More',
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz, color: _muted),
                  ),
                  PopupMenuButton<String>(
                    key: const Key('chrome-menu'),
                    tooltip: 'Menu',
                    color: _search,
                    onSelected: (_) => onOpenSettings(),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'settings',
                            child: Text('Settings'),
                          ),
                        ],
                    icon: const Icon(Icons.menu, color: _muted),
                  ),
                  if (useNativeWindowControls) ...<Widget>[
                    MinimizeWindowButton(key: const Key('chrome-minimize')),
                    MaximizeWindowButton(key: const Key('chrome-maximize')),
                    CloseWindowButton(key: const Key('chrome-close')),
                  ] else ...<Widget>[
                    const SizedBox(key: Key('chrome-minimize'), width: 46),
                    const SizedBox(key: Key('chrome-maximize'), width: 46),
                    const SizedBox(key: Key('chrome-close'), width: 46),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _titleBar(Widget child) =>
      useNativeWindowControls ? WindowTitleBarBox(child: child) : child;
}

class _SearchShell extends StatelessWidget {
  const _SearchShell({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('chrome-search-field'),
    height: 36,
    padding: const EdgeInsets.only(left: 14),
    decoration: BoxDecoration(
      color: DesktopWindowChrome._search,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.search, color: DesktopWindowChrome._muted),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Search Books…',
            style: GoogleFonts.roboto(
              color: DesktopWindowChrome._muted,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(
          height: 20,
          child: VerticalDivider(color: DesktopWindowChrome._muted),
        ),
        IconButton(
          key: const Key('chrome-import'),
          onPressed: onImport,
          icon: const Icon(Icons.add, color: DesktopWindowChrome._muted),
        ),
        IconButton(
          key: const Key('chrome-scan-import'),
          onPressed: onImport,
          icon: const Icon(
            Icons.center_focus_strong,
            color: DesktopWindowChrome._muted,
          ),
        ),
      ],
    ),
  );
}
