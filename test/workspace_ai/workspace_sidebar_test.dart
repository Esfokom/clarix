import 'package:clarix/src/core/theme_profile.dart';
import 'package:clarix/src/features/workspace/domain/workspace_feature_state.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/workspace_common.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/workspace_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('outline expansion has a local Material ink surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Builder(
            builder: (context) {
              final WorkspaceSurfaceTokens colors =
                  WorkspaceSurfaceTokens.fromProfile(
                    const ClarixThemeProfile(),
                    context,
                  );
              return DecoratedBox(
                decoration: BoxDecoration(color: colors.panel),
                child: SizedBox(
                  width: 224,
                  child: OutlinePane(
                    colors: colors,
                    outline: <OutlineNodeState>[
                      OutlineNodeState(
                        title: 'Chapter one',
                        pageNumber: 1,
                        children: <OutlineNodeState>[],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Chapter one'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
