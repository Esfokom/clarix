# Phase 0 PDF Editing Qualification Corpus

The Phase 0 corpus qualifies a PDF adapter against deterministic, licensed
inputs before Clarix relies on it for editing. It is not a product-document
sample set and it must never contain customer files.

## Locations

- `test_fixtures/editing_corpus/manifest.json` is the source of case metadata.
- `generated/` contains repository-owned fixtures created by test tooling.
- `local/` contains ignored private font fixtures used only on the Windows
  qualification machine.

## Safety and reporting

Qualification reports may record a case ID, SHA-256, adapter ID, duration,
page and object counts, capability statuses, warnings, and stable error code.
They must not record extracted text, absolute paths, native handles, font
bytes, or PDF bytes.

The generated cases cover standard Latin text, rotation, multiple text runs,
mixed text/image/vector content, a form XObject, a scanned image page, and
malformed input. The local cases cover a fully embedded TrueType font and a
subset font. Both local cases are required for the Phase 0 exit decision but
are never committed.

## Qualification rule

Each operation is evaluated independently. Successful text import does not
imply clean-patch rendering, materialization, or validation support. An
unsupported operation must report `Unsupported` with a reason and must never
return fabricated success data.

Task 6 adds the deterministic fixture generator and the command used to run
the corpus twice. The two runs must produce identical stable IDs, object
counts, capabilities, and stable error codes.
