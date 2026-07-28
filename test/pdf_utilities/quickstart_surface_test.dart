import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/quickstart_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('startup replaces status cards with four PDF utilities', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(QuickstartSurface(state: _workspaceState())));

    expect(find.text('Fresh launch mode'), findsNothing);
    expect(find.text('AI'), findsNothing);
    expect(find.text('Utilities'), findsOneWidget);
    expect(find.text('Combine PDFs'), findsOneWidget);
    expect(find.text('Convert to PDF'), findsOneWidget);
    expect(find.text('Extract pages'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('Combine PDFs card opens the combine workflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(QuickstartSurface(state: _workspaceState())));
    await tester.tap(find.text('Combine PDFs'));
    await tester.pumpAndSettle();

    expect(find.text('Add PDFs'), findsOneWidget);
    expect(find.text('Combine PDF files'), findsOneWidget);
  });
}

Widget _app(Widget child) => ProviderScope(
  child: ShadApp(
    themeMode: ThemeMode.dark,
    theme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
    ),
    darkTheme: ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadZincColorScheme.dark(),
    ),
    home: Scaffold(body: child),
  ),
);

WorkspaceFeatureState _workspaceState() => WorkspaceFeatureState(
  session: WorkspaceSession.initial().copyWith(
    restorePreviousSession: false,
    recentFiles: const <String>['C:/documents/report.pdf'],
  ),
  aiState: AiWorkspaceState.initial(),
  outlines: const <String, List<OutlineNodeState>>{},
  documentMetadata: const <String, DocumentMetadata>{},
  composerExpanded: false,
  bannerMessage: null,
);
