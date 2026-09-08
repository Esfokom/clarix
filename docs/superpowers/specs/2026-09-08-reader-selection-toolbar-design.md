# Reader selection toolbar

## Purpose

Replace the PDF reader's platform-default text selection menu with a compact
toolbar that keeps the selected passage in context for copy, AI, notes,
bookmarks, read aloud, and persistent highlighting.

## Interaction

PDFRx opens the toolbar automatically after a mouse text selection completes.
It is anchored above the selection when space permits and below it otherwise.
The toolbar contains Copy, Ask AI, Note, Bookmark, Read aloud, every colour in
`ClarixThemeProfile.highlightPalette`, and More colours.

Choosing a colour writes a highlight with the profile's configured opacity and
then clears the PDFRx selection and toolbar. All other actions dismiss the
toolbar. A PDF background click and Escape both dismiss the toolbar and clear
the selection.

## Persistence

Highlights use the same built-in and custom palette persisted by the theme
profile. Notes store the selected text and its page rectangles as a normal
`DocumentAnnotation`, allowing the existing metadata store to restore the
anchor across sessions. Existing page-only notes remain valid.

## Implementation

`ReaderViewerPane` supplies `PdfViewerParams.buildContextMenu` and a custom
toolbar widget. Its callbacks use the selection delegate supplied by PDFRx and
the existing workspace notifier. The notifier accepts optional selected-text
anchors when adding a note. The reader's general-tap and Escape handlers clear
selection state through the same helper.

## Validation

Focused tests cover palette composition, persisted note anchors, colour alpha,
and menu dismissal paths. Existing annotation persistence tests continue to
cover restoration.
