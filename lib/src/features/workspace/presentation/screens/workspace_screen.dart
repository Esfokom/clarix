import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import '../widgets/workspace_body.dart';
import '../widgets/workspace_common.dart';

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final WorkspaceFeatureState? state = ref
        .read(workspaceNotifierProvider)
        .value;
    if (state == null) {
      await windowManager.destroy();
      return;
    }

    if (!state.session.restorePreviousSession &&
        state.session.tabs.isNotEmpty) {
      final bool shouldClose = await _showDiscardDialog();
      if (!shouldClose || !mounted) {
        return;
      }
      await ref
          .read(workspaceNotifierProvider.notifier)
          .discardSessionOnClose();
    }

    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<WorkspaceFeatureState> asyncState = ref.watch(
      workspaceNotifierProvider,
    );

    return Scaffold(
      backgroundColor: WorkspaceColors.canvas,
      body: asyncState.when(
        data: (WorkspaceFeatureState state) => WorkspaceBody(state: state),
        error: (Object error, StackTrace stackTrace) => Center(
          child: SurfaceBlock(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Clarix could not initialize.',
                  style: TextStyle(
                    color: WorkspaceColors.textStrong,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: const TextStyle(
                    color: WorkspaceColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        loading: () => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  Future<bool> _showDiscardDialog() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: WorkspaceColors.panel,
          title: const Text(
            'Close all tabs?',
            style: TextStyle(color: WorkspaceColors.textStrong),
          ),
          content: const Text(
            'Restore previous session is disabled, so closing now will discard the current workspace.',
            style: TextStyle(color: WorkspaceColors.textMuted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Close tabs'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}
