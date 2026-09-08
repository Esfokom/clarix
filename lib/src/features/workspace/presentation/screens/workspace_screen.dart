import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../core/theme_controller.dart';
import '../../../../core/theme_profile.dart';
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
  bool _readerFullscreen = false;
  bool _windowFullscreen = false;
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
    if (notifier.hasUnsavedAnnotations) {
      final choice = await _showUnsavedPdfDialog();
      if (choice == _CloseChoice.cancel || !mounted) return;
      if (choice == _CloseChoice.saveAll) {
        final saved = await notifier.saveAllAnnotations();
        if (!saved || !mounted) return;
      }
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
    final activeTabId = asyncState.value?.session.activeTabId;
    final canSave =
        activeTabId != null &&
        (asyncState.value?.dirtyDocumentIds.contains(activeTabId) ?? false) &&
        !(asyncState.value?.pdfSaveInProgress ?? false);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (canSave) {
            ref
                .read(workspaceNotifierProvider.notifier)
                .saveActiveAnnotations();
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _exitReading();
        },
      },
      child: _readerFullscreen
          ? _workspaceScaffold(asyncState)
          : DesktopWindowChrome(
              showDocumentActions: activeTabId != null,
              onImport: () => ref
                  .read(workspaceNotifierProvider.notifier)
                  .pickAndOpenPdfs(),
              onReaderMode: activeTabId == null ? null : _enterReaderMode,
              onFullscreen: activeTabId == null ? null : _enterFullscreen,
              onOpenSettings: () => showAppSettingsDialog(context),
              onSave: !canSave
                  ? null
                  : () => ref
                        .read(workspaceNotifierProvider.notifier)
                        .saveActiveAnnotations(),
              onSearch: (String query) {
                final String? tabId = asyncState.value?.session.activeTabId;
                if (tabId != null) {
                  ref
                      .read(workspaceNotifierProvider.notifier)
                      .setSearchQuery(tabId, query.trim());
                }
              },
              child: _workspaceScaffold(asyncState),
            ),
    );
  }

  Widget _workspaceScaffold(AsyncValue<WorkspaceFeatureState> asyncState) {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.watch(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    return Scaffold(
      backgroundColor: colors.canvas,
      body: asyncState.when(
        data: (WorkspaceFeatureState state) => WorkspaceBody(
          state: state,
          onOpenSettings: () => showAppSettingsDialog(context),
          fullscreenReader: _readerFullscreen,
          onExitFullscreen: _exitReading,
        ),
        error: (Object error, StackTrace stackTrace) => Center(
          child: SurfaceBlock(
            colors: colors,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Clarix could not initialize.',
                  style: TextStyle(
                    color: colors.textStrong,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
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

  void _enterReaderMode() => setState(() => _readerFullscreen = true);

  Future<void> _enterFullscreen() async {
    setState(() {
      _readerFullscreen = true;
      _windowFullscreen = true;
    });
    await windowManager.setFullScreen(true);
  }

  Future<void> _exitReading() async {
    final bool leaveWindowFullscreen = _windowFullscreen;
    setState(() {
      _readerFullscreen = false;
      _windowFullscreen = false;
    });
    if (leaveWindowFullscreen) await windowManager.setFullScreen(false);
  }

  Future<bool> _showDiscardDialog() async {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: colors.panel,
          title: Text(
            'Close all tabs?',
            style: TextStyle(color: colors.textStrong),
          ),
          content: Text(
            'Restore previous session is disabled, so closing now will discard the current workspace.',
            style: TextStyle(color: colors.textMuted),
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

  Future<_CloseChoice> _showUnsavedPdfDialog() async {
    final colors = WorkspaceSurfaceTokens.fromProfile(
      ref.read(clarixThemeProvider).value ?? const ClarixThemeProfile(),
      context,
    );
    final result = await showDialog<_CloseChoice>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: colors.panel,
        title: Text(
          'Unsaved annotations',
          style: TextStyle(color: colors.textStrong),
        ),
        content: Text(
          'Save every document’s annotations, or close without saving them.',
          style: TextStyle(color: colors.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseChoice.cancel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CloseChoice.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            key: const Key('save-all-annotations'),
            onPressed: () => Navigator.of(context).pop(_CloseChoice.saveAll),
            child: const Text('Save all'),
          ),
        ],
      ),
    );
    return result ?? _CloseChoice.cancel;
  }
}

enum _CloseChoice { cancel, discard, saveAll }
