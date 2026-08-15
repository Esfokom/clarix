import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EditorShortcuts extends StatelessWidget {
  const EditorShortcuts({
    required this.child,
    required this.onEscape,
    this.onUndo,
    this.onRedo,
    super.key,
  });

  final Widget child;
  final VoidCallback onEscape;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
          onUndo ?? _handled,
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): onRedo ?? _handled,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true):
          onRedo ?? _handled,
      // These stay owned by the focused editor and must not scroll pdfrx.
      const SingleActivator(LogicalKeyboardKey.pageUp): _handled,
      const SingleActivator(LogicalKeyboardKey.pageDown): _handled,
    },
    child: child,
  );
}

void _handled() {}
