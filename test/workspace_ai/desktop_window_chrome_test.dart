import 'package:clarix/src/features/workspace/presentation/widgets/desktop_window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows chrome controls and delegates import actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var imports = 0;
    var readerModeRequests = 0;
    var fullscreenRequests = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DesktopWindowChrome(
            onImport: () => imports++,
            onReaderMode: () => readerModeRequests++,
            onFullscreen: () => fullscreenRequests++,
            onOpenSettings: () {},
            onSearch: (_) {},
            useNativeWindowControls: false,
            child: const SizedBox(key: Key('chrome-body')),
          ),
        ),
      ),
    );
    for (final key in <String>[
      'desktop-window-chrome',
      'chrome-search-field',
      'chrome-import',
      'chrome-scan-import',
      'chrome-fullscreen',
      'chrome-overflow',
      'chrome-menu',
      'chrome-minimize',
      'chrome-maximize',
      'chrome-close',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('chrome-import')));
    await tester.tap(find.byKey(const Key('chrome-scan-import')));
    await tester.tap(find.byKey(const Key('chrome-fullscreen')));
    expect(imports, 1);
    expect(readerModeRequests, 1);
    expect(fullscreenRequests, 1);

    final chrome = tester.getRect(
      find.byKey(const Key('desktop-window-chrome')),
    );
    final search = tester.getRect(find.byKey(const Key('chrome-search-field')));
    expect(chrome.height, 56);
    expect(search.left, 24);
    expect(search.top, 10);
    expect(search.width, greaterThan(1000));
    expect(tester.getTopLeft(find.byKey(const Key('chrome-body'))).dy, 56);
  });
}
