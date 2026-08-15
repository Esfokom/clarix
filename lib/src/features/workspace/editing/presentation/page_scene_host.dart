import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/editing/editor_bridge_types.dart';
import '../application/editor_session_controller.dart';
import 'page_surface.dart';

typedef PageSceneBuilder =
    Widget Function(BuildContext context, EditorPageScene scene);

class PageSceneLifecycle extends ChangeNotifier {
  PageSceneLifecycle({
    required this.surface,
    required this.controller,
    this.preloadRadius = 2,
  });

  final PageSurface surface;
  final EditorSessionController controller;
  final int preloadRadius;
  StreamSubscription<Object?>? _documentChanges;
  bool _started = false;

  Set<int> get visiblePages => surface.viewport.visiblePages;

  EditorPageScene? sceneFor(int pageNumber) =>
      controller.state.scenes[pageNumber];

  void start() {
    if (_started) return;
    _started = true;
    surface.addListener(_syncViewport);
    _documentChanges = controller.changes.listen((_) => notifyListeners());
    _syncViewport();
  }

  void _syncViewport() {
    if (!_started || controller.state.isClosed) return;
    controller.updateViewport(
      surface.viewport.visiblePages,
      preloadRadius: preloadRadius,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    if (_started) surface.removeListener(_syncViewport);
    unawaited(_documentChanges?.cancel());
    _started = false;
    super.dispose();
  }
}

class PageSceneHost extends StatelessWidget {
  const PageSceneHost({
    required this.lifecycle,
    required this.pageNumber,
    this.builder,
    super.key,
  });

  final PageSceneLifecycle lifecycle;
  final int pageNumber;
  final PageSceneBuilder? builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: lifecycle,
    builder: (context, _) {
      final scene = lifecycle.sceneFor(pageNumber);
      if (!lifecycle.visiblePages.contains(pageNumber) || scene == null) {
        return const SizedBox.shrink();
      }
      return KeyedSubtree(
        key: ValueKey<String>('page-edit-scene-$pageNumber'),
        child: builder?.call(context, scene) ?? const SizedBox.expand(),
      );
    },
  );
}
