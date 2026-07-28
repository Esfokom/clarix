# PDF utilities design

**Status:** Approved design, awaiting implementation-plan review  
**Date:** 2026-07-28  
**Scope:** Windows desktop Clarix

## Goals

1. Replace the empty-workspace status cards with a practical PDF utilities
   dashboard.
2. Provide offline PDF combination and page extraction without rasterizing or
   otherwise degrading the source documents.
3. Convert images, text, Markdown, DOCX, PPTX, and XLSX to PDF.
4. Export PDF content to Markdown, Word, and PowerPoint with explicit,
   predictable fidelity behavior.

## Non-goals

- Cloud conversion or uploading documents to a third party.
- Claiming that arbitrary PDF layouts can be reconstructed as fully editable
  DOCX or PPTX documents.
- Replacing the existing reader, session restoration, or AI workspace.

## Startup dashboard

The empty workspace keeps the existing welcome header and **Open PDF** action.
It replaces the wide recent-documents panel and the two right-hand cards
(`Fresh launch mode` and AI status) with a primary **Utilities** section.

Utilities are presented as four clear, keyboard-accessible cards:

| Utility | Action |
| --- | --- |
| Combine PDFs | Select multiple PDFs, order them, and produce one PDF. |
| Convert to PDF | Turn supported source files into PDFs. |
| Extract pages | Select page ranges or individual pages and produce one PDF. |
| Export PDF | Export the selected PDF as Markdown, Word, or PowerPoint. |

The recent documents list moves to a compact, fixed-height section at the
bottom of the startup surface. It remains scrollable and retains the existing
reopen behavior.

## Operation model

Each utility opens a modal workflow. Files can be selected through the native
file picker. Combine and convert also accept files dropped onto their dialog
drop zone on desktop. Every workflow validates its inputs before enabling its
primary action, asks the user to choose an output path, displays progress, and
opens the resulting PDF in a new Clarix tab where applicable.

### Combine PDFs

The dialog contains a PDF drop zone, an ordered list of selected files, and
move-up, move-down, and remove controls. Drag reordering is supported in the
list. **Combine** writes a new file composed of the pages in the chosen order.

The Rust PDF layer owns this operation. Its API accepts explicit source paths
and an output path, validates each source, copies page objects into a newly
written document, and returns the output path. Source documents remain
unchanged.

### Extract pages

The dialog accepts one PDF and a page expression, for example `1-3, 7, 9-11`.
The parser normalizes duplicate pages while preserving the written order,
validates bounds against the document page count, and previews the resolved
page count. **Extract** writes a new PDF containing only those pages.

This shares the Rust page-copy writer with Combine. Invalid or encrypted PDFs,
unreadable files, and invalid page expressions report a precise recoverable
message.

## Conversion architecture

`DocumentConversionService` is a Flutter-facing interface selected by source
extension. It owns output-path selection, temporary working directories,
progress/error mapping, and opening generated PDFs. Implementation is split by
conversion family so direct in-app output never depends on LibreOffice.

| Sources | Engine | Result behavior |
| --- | --- | --- |
| PNG, JPG, JPEG, WEBP | In-app Dart PDF writer | One source image per PDF page, preserving aspect ratio. |
| TXT | In-app Dart PDF writer | UTF-8 text with page wrapping and monospace-aware layout. |
| MD, Markdown | In-app Dart PDF writer | Parsed Markdown blocks rendered with headings, lists, code, and links. |
| DOCX, PPTX, XLSX | LibreOffice headless | The source application renderer produces a PDF through an isolated local process. |

LibreOffice discovery checks the standard Windows installation paths and an
optional user-configured executable path. A conversion starts an isolated
headless process with a temporary user profile and output directory, then
checks the expected output file. Missing LibreOffice is a normal actionable
state: Clarix identifies the affected formats and offers the setting to select
an installation. Office conversion never uses a remote service.

## PDF export

`PdfExportService` accepts an existing PDF plus an explicit output format.

- **Markdown:** native text is extracted page-by-page and written as Markdown
  with page headings. Pages with no extractable text are represented with a
  clear marker rather than fabricated text.
- **Word:** a DOCX document contains one page image per PDF page and extracted
  text under each image when available. This produces a faithful visual record
  and selectable/searchable content without implying editable layout fidelity.
- **PowerPoint:** a PPTX presentation has one slide per PDF page, with the page
  rendered as the slide image and extracted text in speaker notes or a hidden
  accessible text area when supported by the generator.

The UI labels the latter two choices as visual exports and explains the
editable-layout limitation before execution.

## Error handling and privacy

- All input/output paths remain local.
- Operations use unique temporary directories and clean them after completion
  or failure.
- Source files are never overwritten; an existing destination requires an
  explicit confirmation in the native save flow.
- Unsupported extensions, missing dependencies, failed processes, corrupted
  PDFs, passwords/encryption, and unavailable output paths each provide a
specific remediation message.
- Partial output is removed on a failed operation; source files are untouched.

## Testing and acceptance criteria

1. Widget tests prove that startup shows the four utilities, excludes both
   retired status cards, and keeps recent documents at the bottom.
2. Combine dialog tests cover add, reorder through buttons and drag, remove,
   validation, and primary-action enablement.
3. Page-expression unit tests cover continuous ranges, disjoint ranges,
   duplicates, reversed ranges, whitespace, and out-of-bounds pages.
4. Rust integration tests use fixture PDFs to verify merged/extracted page
counts and source ordering.
5. Converter tests cover extension routing, direct converter layout planning,
   LibreOffice discovery/command construction, missing-engine guidance, and
   cleanup on failure.
6. Export tests cover Markdown page markers and Word/PowerPoint export plans.
7. Existing workspace, session, reader, and AI tests remain green.

## Delivery order

1. Add the utilities domain/API boundary and page-selection parser with tests.
2. Implement the dashboard and Combine/Extract dialog workflows.
3. Add Rust combine/extract support and fixture integration tests.
4. Add direct image/text/Markdown-to-PDF converters.
5. Add LibreOffice detection, configuration, and Office-to-PDF conversion.
6. Add Markdown, Word, and PowerPoint exports with the stated fidelity model.
