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

  testWidgets('all utility cards are fully visible and hit-testable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(QuickstartSurface(state: _workspaceState())));

    final Rect gridBounds = tester.getRect(find.byType(GridView));
    for (final String label in <String>[
      'Combine PDFs',
      'Convert to PDF',
      'Extract pages',
      'Export PDF',
    ]) {
      final Finder labelFinder = find.text(label);
      final Finder cardFinder = find.ancestor(
        of: labelFinder,
        matching: find.byType(Ink),
      );
      final Rect cardBounds = tester.getRect(cardFinder);

      expect(
        labelFinder.hitTestable(),
        findsOneWidget,
        reason: '$label must accept pointer hit testing',
      );
      expect(
        gridBounds.contains(cardBounds.topLeft),
        isTrue,
        reason: '$label must begin inside the visible grid',
      );
      expect(
        gridBounds.contains(cardBounds.bottomRight - const Offset(1, 1)),
        isTrue,
        reason: '$label must end inside the visible grid',
      );
    }

    await tester.tap(find.text('Extract pages'));
    await tester.pumpAndSettle();
    expect(find.text('Select PDF'), findsOneWidget);
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
