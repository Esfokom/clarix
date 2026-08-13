import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/workspace_providers.dart';
import '../../domain/workspace_feature_state.dart';
import '../widgets/workspace_body.dart';
import '../widgets/workspace_common.dart';
import '../widgets/app_settings_dialog.dart';
import '../widgets/desktop_window_chrome.dart';

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

    final notifier = ref.read(workspaceNotifierProvider.notifier);
    if (notifier.hasUnsavedPdfEdits) {
      final bool shouldClose = await _showUnsavedPdfDialog();
      if (!shouldClose || !mounted) return;
    } else if (!state.session.restorePreviousSession &&
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
    final editing = ref.watch(pdfEditingControllerProvider);
    final activeTabId = asyncState.value?.session.activeTabId;
    final canSave =
        activeTabId == null ||
        (editing.sessionsByTabId[activeTabId]?.overflowingLocators.isEmpty ??
            true);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            ref.read(workspaceNotifierProvider.notifier).saveActivePdfEdits(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            ref.read(workspaceNotifierProvider.notifier).undoPdfEdit(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () =>
            ref.read(workspaceNotifierProvider.notifier).redoPdfEdit(),
      },
      child: DesktopWindowChrome(
        onImport: () =>
            ref.read(workspaceNotifierProvider.notifier).pickAndOpenPdfs(),
        onOpenSettings: () => showAppSettingsDialog(context),
        onSave: asyncState.value?.session.activeTabId == null || !canSave
            ? null
            : () => ref
                  .read(workspaceNotifierProvider.notifier)
                  .saveActivePdfEdits(),
        onUndo: ref.read(workspaceNotifierProvider.notifier).canUndoActive
            ? () => ref.read(workspaceNotifierProvider.notifier).undoPdfEdit()
            : null,
        onRedo: ref.read(workspaceNotifierProvider.notifier).canRedoActive
            ? () => ref.read(workspaceNotifierProvider.notifier).redoPdfEdit()
            : null,
        onSearch: (String query) {
          final String? tabId = asyncState.value?.session.activeTabId;
          if (tabId != null) {
            ref
                .read(workspaceNotifierProvider.notifier)
                .setSearchQuery(tabId, query.trim());
          }
        },
        child: Scaffold(
          backgroundColor: WorkspaceColors.canvas,
          body: asyncState.when(
            data: (WorkspaceFeatureState state) => WorkspaceBody(
              state: state,
              onOpenSettings: () => showAppSettingsDialog(context),
            ),
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

  Future<bool> _showUnsavedPdfDialog() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: WorkspaceColors.panel,
        title: const Text(
          'Discard unsaved PDF edits?',
          style: TextStyle(color: WorkspaceColors.textStrong),
        ),
        content: const Text(
          'Bookmarks and highlights have not been saved into their PDF files. Closing now will lose those changes.',
          style: TextStyle(color: WorkspaceColors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
