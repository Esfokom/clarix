import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/infrastructure/workspace_preset_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('WorkspacePresetStore saves, lists, and deletes presets correctly', () async {
    final store = WorkspacePresetStore(preferences: SharedPreferencesAsync());

    expect(await store.readPresets(), isEmpty);

    final tab = DocumentTabState.create(
      id: 'tab-1',
      documentId: 'doc-1',
      filePath: r'C:\docs\test.pdf',
      title: 'Test PDF',
    ).copyWith(
      currentPage: 5,
      zoomScale: 1.0,
      scrollOffsetX: 0,
      scrollOffsetY: 0,
      indexStatus: DocumentIndexStatus.indexed,
      lastOpenedAt: DateTime.parse('2026-09-07T10:00:00.000Z'),
    );

    final session = WorkspaceSession(
      restorePreviousSession: true,
      tabs: [tab],
      activeTabId: 'tab-1',
      lastOpenedAt: DateTime.parse('2026-09-07T10:00:00.000Z'),
      recentFiles: [r'C:\docs\test.pdf'],
      sidebarPane: SidebarPane.outline,
      leftPaneWidth: 250,
      rightPaneWidth: 400,
      leftPaneCollapsed: false,
      rightPaneCollapsed: true,
      rightToolWindow: RightToolWindow.none,
      studyModeFullScreen: false,
    );

    final preset = WorkspacePreset(
      id: 'preset-1',
      name: 'Research Workspace',
      createdAt: DateTime.parse('2026-09-07T10:05:00.000Z'),
      session: session,
    );

    await store.savePreset(preset);

    final savedPresets = await store.readPresets();
    expect(savedPresets, hasLength(1));
    expect(savedPresets.first.name, 'Research Workspace');
    expect(savedPresets.first.tabCount, 1);
    expect(savedPresets.first.session.tabs.first.title, 'Test PDF');

    await store.deletePreset('preset-1');
    expect(await store.readPresets(), isEmpty);
  });
}
