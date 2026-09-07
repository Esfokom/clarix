import 'dart:io';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/application/workspace_providers.dart';
import 'package:clarix/src/features/workspace/infrastructure/document_metadata_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('WorkspaceNotifier route navigation history and StudyMode full screen exit', () async {
    final SharedPreferencesAsync preferences = SharedPreferencesAsync();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        documentMetadataStoreProvider.overrideWith(
          (Ref ref) async =>
              DocumentMetadataStore(root: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Initial state rehydrates session
    await container.read(workspaceNotifierProvider.future);
    final notifier = container.read(workspaceNotifierProvider.notifier);

    expect(notifier.canGoBack, isFalse);

    // 1. Open StudyMode tool window
    await notifier.selectRightToolWindow(RightToolWindow.studyMode);
    expect(
      container.read(workspaceNotifierProvider).requireValue.session.rightToolWindow,
      RightToolWindow.studyMode,
    );
    expect(notifier.canGoBack, isTrue);

    // 2. Toggle full screen study mode
    await notifier.setStudyModeFullScreen(true);
    var currentSession = container.read(workspaceNotifierProvider).requireValue.session;
    expect(currentSession.studyModeFullScreen, isTrue);
    expect(currentSession.rightToolWindow, RightToolWindow.studyMode);

    // 3. Navigate home
    await notifier.navigateHome();
    currentSession = container.read(workspaceNotifierProvider).requireValue.session;
    expect(currentSession.activeTabId, isNull);
    expect(currentSession.rightToolWindow, RightToolWindow.none);
    expect(currentSession.studyModeFullScreen, isFalse); // Fullscreen StudyMode cleared on Home!

    // 4. Test Go Back (should return to FullScreen StudyMode)
    await notifier.goBack();
    currentSession = container.read(workspaceNotifierProvider).requireValue.session;
    expect(currentSession.studyModeFullScreen, isTrue);
    expect(currentSession.rightToolWindow, RightToolWindow.studyMode);

    // 5. Test Go Back again (should return to SidePane StudyMode)
    await notifier.goBack();
    currentSession = container.read(workspaceNotifierProvider).requireValue.session;
    expect(currentSession.studyModeFullScreen, isFalse);
    expect(currentSession.rightToolWindow, RightToolWindow.studyMode);

    // 6. Test Go Back again (should return to Home)
    await notifier.goBack();
    currentSession = container.read(workspaceNotifierProvider).requireValue.session;
    expect(currentSession.activeTabId, isNull);
    expect(currentSession.rightToolWindow, RightToolWindow.none);
    expect(notifier.canGoBack, isFalse);
  });
}
