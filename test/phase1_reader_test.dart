import 'dart:io';
import 'dart:ui';

import 'package:clarix/src/core/models.dart';
import 'package:clarix/src/features/workspace/infrastructure/document_metadata_store.dart';
import 'package:clarix/src/features/workspace/presentation/widgets/pdf_viewer_interaction_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test(
    'cursor-locked PDF normalization preserves the affine camera matrix',
    () {
      final Matrix4 matrix = Matrix4.identity()
        ..setEntry(0, 0, 1.72)
        ..setEntry(1, 1, 1.72)
        ..setEntry(0, 3, -232.704)
        ..setEntry(1, 3, -175.68);

      expect(preserveReaderCursorLockedMatrix(matrix), same(matrix));
    },
  );

  test('instrumented focal remains at the pinch-start cursor', () {
    final Offset focal = resolveLockedPointerFocalPoint(
      lockedFocalPoint: const Offset(723.2, 544),
      reportedFocalPoint: const Offset(191.746826171875, 144.234521484375),
    );

    expect(focal, const Offset(723.2, 544));
  });

  test('reader zoom keeps the cursor fixed despite trackpad pan noise', () {
    final Offset anchor = resolveReaderZoomFocalPoint(
      trackedCursorLocal: const Offset(723.2, 544),
      reportedTrackpadFocalPoint: const Offset(
        191.746826171875,
        144.234521484375,
      ),
      viewportSize: const Size(1485.6, 844),
    );

    expect(anchor, const Offset(723.2, 544));
  });

  test(
    'reader zoom prefers the tracked cursor over trackpad focal corners',
    () {
      final Offset anchor = resolveReaderZoomFocalPoint(
        trackedCursorLocal: const Offset(237, 181),
        reportedTrackpadFocalPoint: Offset.zero,
        viewportSize: const Size(800, 600),
      );

      expect(anchor, const Offset(237, 181));
    },
  );

  test('reader zoom rejects a stale cursor outside the viewport', () {
    final Offset anchor = resolveReaderZoomFocalPoint(
      trackedCursorLocal: const Offset(920, 181),
      reportedTrackpadFocalPoint: const Offset(410, 305),
      viewportSize: const Size(800, 600),
    );

    expect(anchor, const Offset(410, 305));
  });

  test('PDF zoom anchor rejects a non-finite viewer conversion', () {
    final Offset anchor = resolvePdfZoomAnchor(
      globalPosition: const Offset(520, 340),
      fallbackLocalPosition: const Offset(400, 300),
      globalToLocal: (_) => const Offset(double.nan, double.infinity),
    );

    expect(anchor, const Offset(400, 300));
  });

  test('document metadata round-trips through the sidecar store', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'clarix-metadata-',
    );
    addTearDown(() => root.delete(recursive: true));
    final DocumentMetadataStore store = DocumentMetadataStore(root: root);
    final DocumentIdentity identity = DocumentIdentity(
      fingerprint: 'a' * 64,
      path: r'C:\docs\paper.pdf',
      title: 'paper.pdf',
      byteLength: 512,
      modifiedAt: DateTime.utc(2026, 7, 14),
      pageCount: 4,
      isEncrypted: false,
    );
    final DocumentMetadata metadata = DocumentMetadata(
      identity: identity,
      bookmarks: <DocumentBookmark>[
        DocumentBookmark(
          id: 'bookmark-1',
          pageNumber: 3,
          label: 'Results',
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
      annotations: <DocumentAnnotation>[
        DocumentAnnotation(
          id: 'annotation-1',
          kind: AnnotationKind.highlight,
          pageNumber: 2,
          pageRects: const <Rect>[Rect.fromLTWH(10, 20, 100, 14)],
          selectedText: 'local-first',
          note: null,
          colorValue: 0x66FFD54F,
          createdAt: DateTime.utc(2026, 7, 14),
        ),
      ],
    );

    await store.write(metadata);
    final DocumentMetadata? restored = await store.read(identity.fingerprint);

    expect(restored, isNotNull);
    expect(restored!.identity.path, identity.path);
    expect(restored.bookmarks.single.pageNumber, 3);
    expect(
      restored.annotations.single.pageRects.single,
      const Rect.fromLTWH(10, 20, 100, 14),
    );
  });

  test('document identity is stable when a file is moved', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'clarix-fingerprint-',
    );
    addTearDown(() => root.delete(recursive: true));
    final File first = File('${root.path}${Platform.pathSeparator}one.pdf');
    final File moved = File('${root.path}${Platform.pathSeparator}two.pdf');
    await first.writeAsBytes(List<int>.generate(4096, (int i) => i % 251));

    final DocumentIdentityService identities = DocumentIdentityService();
    final DocumentIdentity before = await identities.identify(first.path);
    await first.rename(moved.path);
    final DocumentIdentity after = await identities.identify(moved.path);

    expect(after.fingerprint, before.fingerprint);
    expect(after.path, moved.path);
  });
}
