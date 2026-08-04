# Resizable workspace panes and citation navigation

## Goal

Make the left reader sidebar and right AI pane resizable/collapsible, and make AI citations previewable and navigable in the already-open PDF.

## Pane layout

Persist left/right widths and collapsed states in `WorkspaceSession`. Both panes have constrained drag dividers (200–480 logical pixels when expanded) and a compact center-edge toggle that remains accessible while collapsed. Resizing and collapsing never replace or reload the central PDF reader.

## Citation interactions

Assistant messages render their existing retrieval citations as `Page N` chips below the answer. Hovering a chip opens a preview card containing a small `PdfPageView` from the existing document reference. Clicking a chip selects the cited tab if needed and requests an animated jump to the cited page.

## Navigation

The workspace owns a one-shot page-navigation request keyed by document ID and page number. The matching live PDF viewer consumes it and invokes its existing controller’s animated page navigation. No PDF file is reopened or reparsed.

## Tests

Tests cover width clamping/persistence, collapsed toggle behavior, citation-chip preview and click dispatch, and one-shot page-navigation consumption.
