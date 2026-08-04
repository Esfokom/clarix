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
      const MaterialApp(
        home: Material(
          child: DecoratedBox(
            decoration: BoxDecoration(color: WorkspaceColors.panel),
            child: SizedBox(
              width: 224,
              child: OutlinePane(
                outline: <OutlineNodeState>[
                  OutlineNodeState(
                    title: 'Chapter one',
                    pageNumber: 1,
                    children: <OutlineNodeState>[],
                  ),
                ],
              ),
            ),
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
