# PDF Utilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the empty-workspace status cards with a fully local PDF utility dashboard that combines, extracts, converts, and exports documents.

**Architecture:** Flutter owns workflows, dialogs, native file selection, output selection, and current-document opening. Rust owns lossless PDF page composition through a narrow FFI surface. Format-specific services isolate direct Dart conversion, LibreOffice process conversion, and OOXML/Markdown export behind testable interfaces.

**Tech Stack:** Flutter/Dart, Riverpod, shadcn_ui, flutter_rust_bridge, Rust, lopdf, pdfrx, pdf, markdown, archive, file_picker, LibreOffice headless.

## Global Constraints

- Target Windows desktop Clarix; all conversion is local and must not upload a document.
- Never overwrite or mutate source files; write through a unique temporary output and replace only the selected destination on success.
- Combine and Extract preserve original PDF page objects rather than rasterizing pages.
- Direct conversion covers PNG/JPG/JPEG/WEBP, TXT, and Markdown; DOCX/PPTX/XLSX uses a detected local LibreOffice executable.
- Word and PowerPoint exports must be labelled visual exports: a rendered page image plus extracted text, not arbitrary editable-layout reconstruction.
- Regenerate flutter_rust_bridge bindings after every public Rust FFI change with `flutter_rust_bridge_codegen generate` from `rust/clarix_pdf_oxide`.

---

## File structure

| File | Responsibility |
| --- | --- |
| `lib/src/features/utilities/domain/pdf_page_selection.dart` | Immutable range parser and page validation. |
| `lib/src/features/utilities/domain/utility_job.dart` | Utility formats, progress, result, and failure value types. |
| `lib/src/features/utilities/application/pdf_utility_service.dart` | Flutter facade over native compose/extract plus source/output safety. |
| `lib/src/features/utilities/infrastructure/document_conversion_service.dart` | Extension routing and direct conversion orchestration. |
| `lib/src/features/utilities/infrastructure/libreoffice_converter.dart` | Windows discovery and isolated headless LibreOffice process. |
| `lib/src/features/utilities/infrastructure/pdf_export_service.dart` | Markdown, visual DOCX, and visual PPTX export orchestration. |
| `lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart` | Combine, Convert, Extract, and Export modal workflows. |
| `lib/src/features/workspace/presentation/widgets/quickstart_surface.dart` | Utilities dashboard and compact bottom recents section. |
| `rust/clarix_pdf_oxide/src/api.rs` | FFI-safe request/response types and native compose/extract endpoints. |
| `rust/clarix_pdf_oxide/src/pdf_compose.rs` | `lopdf` page copy implementation with atomic write handling. |

### Task 1: Establish utility contracts and dependency boundary

**Files:**
- Create: `lib/src/features/utilities/domain/pdf_page_selection.dart`
- Create: `lib/src/features/utilities/domain/utility_job.dart`
- Test: `test/pdf_utilities/pdf_page_selection_test.dart`
- Modify: `pubspec.yaml`

**Produces:** `PdfPageSelection.parse(String expression, {required int pageCount})`, `UtilityFormat`, `UtilityResult`, and `UtilityFailure` used by every later workflow.

- [ ] **Step 1: Write failing range-parser tests**

```dart
test('keeps written range order and removes later duplicates', () {
  expect(PdfPageSelection.parse('3-4, 1, 3', pageCount: 4).pages, [3, 4, 1]);
});
test('rejects an out-of-bounds page', () {
  expect(() => PdfPageSelection.parse('1, 8', pageCount: 7), throwsFormatException);
});
```

- [ ] **Step 2: Run the test and verify the missing implementation fails**

Run: `flutter test test/pdf_utilities/pdf_page_selection_test.dart`

- [ ] **Step 3: Implement immutable contracts and add packages**

```dart
final class PdfPageSelection {
  const PdfPageSelection._(this.pages);
  final List<int> pages;
  factory PdfPageSelection.parse(String expression, {required int pageCount}) { /* tokenize 1-3, 7 */ }
}
enum UtilityFormat { combine, convertToPdf, extractPages, markdown, word, powerpoint }
```

Add `pdf`, `markdown`, and `archive` to `pubspec.yaml`; run `flutter pub get`.

- [ ] **Step 4: Run focused tests and static analysis**

Run: `flutter test test/pdf_utilities/pdf_page_selection_test.dart && flutter analyze`

- [ ] **Step 5: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/src/features/utilities/domain test/pdf_utilities
git commit -m "feat: add PDF utility contracts"
```

### Task 2: Add lossless Rust page composition and FFI

**Files:**
- Modify: `rust/clarix_pdf_oxide/Cargo.toml`
- Create: `rust/clarix_pdf_oxide/src/pdf_compose.rs`
- Modify: `rust/clarix_pdf_oxide/src/lib.rs`
- Modify: `rust/clarix_pdf_oxide/src/api.rs`
- Modify: `lib/src/core/ffi/*.dart` (generated)
- Test: `rust/clarix_pdf_oxide/src/pdf_compose.rs`

**Consumes:** ordered source paths and page selections.  
**Produces:** `compose_pdfs(request: NativePdfComposeRequest) -> NativePdfComposeResponse`, with `output_path`, `page_count`, and an actionable `message` on failure.

- [ ] **Step 1: Add Rust tests using two small fixture PDFs**

```rust
#[test]
fn compose_preserves_requested_page_order() {
    compose_pdfs(ComposeRequest::from_pages(&["first.pdf", "second.pdf"], &[1, 2]));
    assert_eq!(PdfDocument::open("merged.pdf").unwrap().page_count().unwrap(), 2);
}
```

- [ ] **Step 2: Run the crate test and verify failure**

Run: `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml pdf_compose`

- [ ] **Step 3: Implement composition with `lopdf`**

```rust
pub fn compose_pdfs(request: NativePdfComposeRequest) -> NativePdfComposeResponse {
    // load each source, renumber imported objects, append requested pages,
    // save to output_path + ".partial", then atomically rename on success
}
```

Add `lopdf` to Cargo.toml. Define FFI-safe `NativePdfSource { path, pages }` and `NativePdfComposeRequest { sources, output_path }`; map parser/open/save errors to response messages. Export through `api.rs`, regenerate bindings, and retain the existing reader API untouched.

- [ ] **Step 4: Verify native and generated boundaries**

Run: `cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml && flutter_rust_bridge_codegen generate && flutter analyze`

- [ ] **Step 5: Commit**

```powershell
git add rust/clarix_pdf_oxide lib/src/core/ffi
git commit -m "feat: compose PDF pages in Rust"
```

### Task 3: Build the Flutter utility facade and output safety

**Files:**
- Create: `lib/src/features/utilities/application/pdf_utility_service.dart`
- Modify: `lib/src/features/workspace/application/workspace_providers.dart`
- Test: `test/pdf_utilities/pdf_utility_service_test.dart`

**Consumes:** `PdfPageSelection`, `NativePdfComposeRequest`, `FilePicker`.  
**Produces:** `PdfUtilityService.combine`, `PdfUtilityService.extract`, and `PdfUtilityService.openGeneratedPdf`.

- [ ] **Step 1: Write failing facade tests with a fake native composer**

```dart
test('extract delegates one selected source in requested page order', () async {
  await service.extract(sourcePath: 'in.pdf', pages: const [4, 2], outputPath: 'out.pdf');
  expect(native.requests.single.sources.single.pages, [4, 2]);
});
```

- [ ] **Step 2: Run the service test and verify failure**

Run: `flutter test test/pdf_utilities/pdf_utility_service_test.dart`

- [ ] **Step 3: Implement the facade**

```dart
abstract interface class PdfComposeNative {
  Future<NativePdfComposeResponse> compose(NativePdfComposeRequest request);
}
final class PdfUtilityService {
  Future<UtilityResult> combine({required List<String> sources, required String outputPath});
  Future<UtilityResult> extract({required String sourcePath, required List<int> pages, required String outputPath});
}
```

Reject zero sources, duplicate output/source paths, and non-PDF extensions before FFI. Convert native errors to `UtilityFailure`, and only call the existing notifier `openPdfFiles` after a successful resulting PDF exists.

- [ ] **Step 4: Run focused tests**

Run: `flutter test test/pdf_utilities/pdf_utility_service_test.dart && flutter analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/utilities lib/src/features/workspace/application/workspace_providers.dart test/pdf_utilities
git commit -m "feat: add PDF utility service"
```

### Task 4: Replace the startup cards and deliver Combine/Extract workflows

**Files:**
- Modify: `lib/src/features/workspace/presentation/widgets/quickstart_surface.dart`
- Create: `lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart`
- Modify: `lib/src/features/workspace/application/workspace_notifier.dart`
- Test: `test/pdf_utilities/quickstart_surface_test.dart`
- Test: `test/pdf_utilities/pdf_utilities_dialogs_test.dart`

**Consumes:** `PdfUtilityService`.  
**Produces:** `showCombinePdfDialog`, `showExtractPagesDialog`, and dashboard utility cards.

- [ ] **Step 1: Write startup and dialog widget tests**

```dart
expect(find.text('Fresh launch mode'), findsNothing);
expect(find.text('Utilities'), findsOneWidget);
await tester.tap(find.text('Combine PDFs'));
expect(find.text('Add PDFs'), findsOneWidget);
```

- [ ] **Step 2: Run the widget tests and verify failure**

Run: `flutter test test/pdf_utilities/quickstart_surface_test.dart test/pdf_utilities/pdf_utilities_dialogs_test.dart`

- [ ] **Step 3: Implement the dashboard and dialogs**

```dart
class _CombinePdfDialogState extends State<CombinePdfDialog> {
  final files = <String>[];
  void move(int from, int to) => setState(() { final path = files.removeAt(from); files.insert(to, path); });
}
```

Show a two-column utility card grid above a fixed-height `SurfaceBlock` recents list. Use `ReorderableListView`, add/remove controls, `ShadDialog`, and native file selection. Extract uses a single selected PDF, loads its page count, validates `PdfPageSelection`, selects a destination, awaits the service, and calls a notifier method that opens only the successful result.

- [ ] **Step 4: Run dashboard regressions**

Run: `flutter test test/pdf_utilities test/widget_test.dart && flutter analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/workspace/presentation lib/src/features/workspace/application test/pdf_utilities
git commit -m "feat: add startup PDF utilities"
```

### Task 5: Implement local source-to-PDF conversion

**Files:**
- Create: `lib/src/features/utilities/infrastructure/document_conversion_service.dart`
- Create: `lib/src/features/utilities/infrastructure/libreoffice_converter.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart`
- Test: `test/pdf_utilities/document_conversion_service_test.dart`
- Test: `test/pdf_utilities/libreoffice_converter_test.dart`

**Produces:** `DocumentConversionService.convert(List<String>, String outputDirectory)` and `LibreOfficeConverter.convert(String inputPath, String outputPath)`.

- [ ] **Step 1: Write routing and process tests**

```dart
test('routes markdown to the direct PDF converter', () async {
  await service.convert(sourcePath: 'notes.md', outputPath: 'notes.pdf');
  verify(() => direct.convertMarkdown('notes.md', 'notes.pdf')).called(1);
});
test('reports a helpful failure when LibreOffice is absent', () async {
  expect(await converter.discover(), isNull);
});
```

- [ ] **Step 2: Run converter tests and verify failure**

Run: `flutter test test/pdf_utilities/document_conversion_service_test.dart test/pdf_utilities/libreoffice_converter_test.dart`

- [ ] **Step 3: Implement direct and LibreOffice conversion**

```dart
switch (extension) {
  case '.png' || '.jpg' || '.jpeg' || '.webp': return _direct.imagesToPdf(...);
  case '.txt': return _direct.textToPdf(...);
  case '.md' || '.markdown': return _direct.markdownToPdf(...);
  case '.docx' || '.pptx' || '.xlsx': return _office.convert(...);
}
```

Use `pdf` for A4 layout, aspect-ratio-constrained image pages, UTF-8 text pagination, and parsed Markdown blocks. Search `C:\\Program Files\\LibreOffice\\program\\soffice.com` then `C:\\Program Files (x86)\\LibreOffice\\program\\soffice.com`; invoke `--headless --nologo --nolockcheck -env:UserInstallation=file:///... --convert-to pdf --outdir ... input`. Require the expected PDF to exist and clean the temporary profile and directory in `finally`.

- [ ] **Step 4: Wire Convert to PDF dialog and verify**

Run: `flutter test test/pdf_utilities/document_conversion_service_test.dart test/pdf_utilities/libreoffice_converter_test.dart test/pdf_utilities/pdf_utilities_dialogs_test.dart && flutter analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/utilities lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart test/pdf_utilities pubspec.yaml pubspec.lock
git commit -m "feat: convert files to PDF locally"
```

### Task 6: Implement PDF-to-Markdown, Word, and PowerPoint exports

**Files:**
- Create: `lib/src/features/utilities/infrastructure/pdf_export_service.dart`
- Create: `lib/src/features/utilities/infrastructure/ooxml_visual_export.dart`
- Modify: `lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart`
- Test: `test/pdf_utilities/pdf_export_service_test.dart`
- Test: `test/pdf_utilities/ooxml_visual_export_test.dart`

**Consumes:** `HybridPdfExtractionService.extractDocumentText`, `pdfrx.PdfDocument.openFile`, `PdfPage.render`, and `archive.ArchiveEncoder`.  
**Produces:** `PdfExportService.export(sourcePath, format, outputPath)`.

- [ ] **Step 1: Write export contract tests**

```dart
test('markdown writes an explicit heading for every PDF page', () async {
  await service.export(sourcePath: 'report.pdf', format: UtilityFormat.markdown, outputPath: 'report.md');
  expect(await output.readAsString(), contains('## Page 2'));
});
test('Word visual export contains a relationship for every rendered page', () async {
  final zip = ZipDecoder().decodeBytes(await File('report.docx').readAsBytes());
  expect(zip.findFile('word/media/page-2.png'), isNotNull);
});
```

- [ ] **Step 2: Run export tests and verify failure**

Run: `flutter test test/pdf_utilities/pdf_export_service_test.dart test/pdf_utilities/ooxml_visual_export_test.dart`

- [ ] **Step 3: Implement Markdown and visual OOXML writers**

```dart
Future<UtilityResult> export({required String sourcePath, required UtilityFormat format, required String outputPath}) async {
  final pages = await extraction.extractDocumentText(sourcePath);
  return switch (format) { UtilityFormat.markdown => _writeMarkdown(pages, outputPath), UtilityFormat.word => _writeDocx(...), UtilityFormat.powerpoint => _writePptx(...), _ => throw ArgumentError.value(format) };
}
```

Render every PDF page at 150 DPI with pdfrx, write DOCX package parts (`[Content_Types].xml`, relationships, `word/document.xml`, images) and PPTX parts (presentation, slide, relationships, images) via `archive`. Place extracted text beneath each Word image and in a hidden accessible text box on each PowerPoint slide. Mark blank extraction as `[No extractable text on this page.]`.

- [ ] **Step 4: Add Export PDF dialog and verify full feature suite**

Run: `flutter test test/pdf_utilities test/widget_test.dart && flutter analyze && cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/utilities lib/src/features/workspace/presentation/widgets/pdf_utilities_dialogs.dart test/pdf_utilities
git commit -m "feat: export PDFs to Markdown Word and PowerPoint"
```

### Task 7: Verify Windows packaging and manual acceptance paths

**Files:**
- Modify: `README.md`
- Create: `docs/testing/pdf-utilities-manual-checklist.md`

**Consumes:** all previous services and workflows.  
**Produces:** repeatable developer instructions and release acceptance evidence.

- [ ] **Step 1: Add a failing documentation audit test**

```dart
test('supported source types remain centrally declared', () {
  expect(DocumentConversionService.supportedExtensions, containsAll(<String>{'.docx', '.pptx', '.xlsx', '.md', '.png'}));
});
```

- [ ] **Step 2: Run it and verify failure if the declaration is absent**

Run: `flutter test test/pdf_utilities/document_conversion_service_test.dart`

- [ ] **Step 3: Add the supported-extension declaration and manual checklist**

Document build prerequisites (`flutter_rust_bridge_codegen`, Rust toolchain, optional LibreOffice), missing-LibreOffice UX, combine ordering, extraction expressions, each direct conversion, and each export fidelity notice. Include a checklist to open generated PDFs in Clarix and to inspect generated `.docx`/`.pptx` packages in Office/LibreOffice.

- [ ] **Step 4: Run final automated verification**

Run: `flutter test && flutter analyze && cargo test --manifest-path rust/clarix_pdf_oxide/Cargo.toml`

- [ ] **Step 5: Commit**

```powershell
git add README.md docs/testing test/pdf_utilities lib/src/features/utilities
git commit -m "docs: document PDF utilities verification"
```

## Plan self-review

- **Spec coverage:** Tasks 2–4 cover startup, combine, and extraction; Task 5 covers every requested incoming source type; Task 6 covers all requested outgoing formats and fidelity notices; Task 7 records the Windows verification path.
- **No placeholders:** every task names concrete files, interfaces, test commands, and a commit boundary.
- **Boundary consistency:** all Flutter PDF manipulation is exposed by `PdfUtilityService`; `DocumentConversionService` and `PdfExportService` remain separate from workspace state; only the successful result flows back to `WorkspaceNotifier.openPdfFiles`.
