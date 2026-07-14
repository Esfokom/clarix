# Phase 1 Reader Test Matrix

| Scenario | Open | Search | Navigation | Persist/reopen | Annotation | Expected recovery |
|---|---:|---:|---:|---:|---:|---|
| Born-digital PDF | Yes | Native text + bounding boxes | Pages and outline | Page, zoom, bookmarks, notes | Highlight + note | N/A |
| Scanned PDF | Yes | OCR after local model install | Pages and thumbnails | OCR sidecar retained | Note; OCR highlight after bridge generation | Resume failed/cancelled OCR |
| Rotated pages | Yes | Correct page coordinates | Correct orientation | Yes | Highlight remains aligned | N/A |
| Large PDF | Progressive | Incremental | Lazy thumbnails | Yes | Yes | Bounded image/text caches |
| Moved file | Missing state | Disabled until located | Locate action | New path retained | Sidecar retained | SHA-256 must match |
| Wrong replacement | Remains missing | No | No | Original entry retained | Sidecar retained | Reject fingerprint mismatch |
| Corrupted PDF | Error surface | No | No | Session remains recoverable | No | Clear local error |
| Encrypted PDF | Password flow/fallback | After unlock | After unlock | No password persisted | After unlock | Never transmit contents |

## Interaction checks

- Zoom at the four viewport quadrants and compare `localToDocument(anchor)` before and after; error must be at most one logical pixel.
- Validate mouse wheel, Ctrl+wheel, precision trackpad, pinch, toolbar zoom, fit-width, and fit-page.
- Drag the page and both custom scrollbars; toolbar pointer events must not replace the last document anchor.
- Resize the window at non-default zoom and confirm the visible document region does not jump unexpectedly.

## Offline check

After Gemma, EmbeddingGemma, and OCR model assets are installed, disable networking and repeat open, search, annotation, OCR, indexing, and local inference checks. Model download failures must not block the PDF reader.
