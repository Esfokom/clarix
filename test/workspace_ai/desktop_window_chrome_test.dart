import 'package:clarix/src/features/workspace/presentation/widgets/desktop_window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows chrome controls and delegates import actions', (
    tester,
  ) async {
    var imports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopWindowChrome(
          onImport: () => imports++,
          onOpenSettings: () {},
          useNativeWindowControls: false,
          child: const SizedBox(key: Key('chrome-body')),
        ),
      ),
    );
    for (final key in <String>[
      'desktop-window-chrome',
      'chrome-search-field',
      'chrome-import',
      'chrome-scan-import',
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
    expect(imports, 2);
    expect(
      tester.getTopLeft(find.byKey(const Key('chrome-body'))).dy,
      greaterThanOrEqualTo(48),
    );
  });
}
