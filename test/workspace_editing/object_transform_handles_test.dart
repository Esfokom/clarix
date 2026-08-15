import 'package:clarix/src/core/editing/editor_bridge_types.dart';
import 'package:clarix/src/features/workspace/editing/presentation/object_transform_handles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_editor_harness.dart';

void main() {
  for (final scale in <double>[0.75, 2]) {
    testWidgets('move gesture submits one PDF-space command at ${scale}x', (
      tester,
    ) async {
      final harness = NativeEditorTestHarness();
      await harness.open();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 420 * scale,
            height: 72 * scale,
            child: ObjectTransformHandles(
              session: harness.controller,
              object: harness.gateway.object,
              pageSize: const Size(420, 72),
              displaySize: Size(420 * scale, 72 * scale),
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const Key('move-object-handle')),
        Offset(30 * scale, -12 * scale),
      );
      await tester.pump();

      expect(harness.gateway.requests, hasLength(1));
      final command = harness.gateway.requests.single.payload;
      expect(command.kind, EditorCommandKind.moveObject);
      expect(command.transform?.e, closeTo(30, 0.01));
      expect(command.transform?.f, closeTo(12, 0.01));
      await tester.runAsync(harness.controller.close);
    });
  }

  testWidgets('resize and rotate each submit exactly one typed command', (
    tester,
  ) async {
    final harness = NativeEditorTestHarness();
    await harness.open();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 840,
          height: 108,
          child: ObjectTransformHandles(
            session: harness.controller,
            object: harness.gateway.object,
            pageSize: const Size(420, 72),
            displaySize: const Size(630, 108),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const Key('resize-object-handle')),
      const Offset(30, 12),
    );
    await tester.pump();
    final resize = harness.gateway.requests.single.payload;
    expect(resize.kind, EditorCommandKind.resizeObject);
    expect(resize.bounds?.right, closeTo(440, 0.01));
    expect(resize.bounds?.bottom, closeTo(-8, 0.01));

    harness.gateway.requests.clear();
    await tester.drag(
      find.byKey(const Key('rotate-object-handle')),
      const Offset(20, 10),
    );
    await tester.pump();
    final rotate = harness.gateway.requests.single.payload;
    expect(rotate.kind, EditorCommandKind.rotateObject);
    expect(rotate.radians, isNot(0));
    await tester.runAsync(harness.controller.close);
  });

  testWidgets('Escape cancels a local transform preview without a command', (
    tester,
  ) async {
    final harness = NativeEditorTestHarness();
    await harness.open();
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectTransformHandles(
          session: harness.controller,
          object: harness.gateway.object,
          pageSize: const Size(420, 72),
          displaySize: const Size(420, 72),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('move-object-handle'))),
    );
    await gesture.moveBy(const Offset(20, 10));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pump();

    expect(harness.gateway.requests, isEmpty);
    await tester.runAsync(harness.controller.close);
  });
}
