# PDF Bookmarks and Highlights Design

## Goal

Allow users to create, inspect, rename, navigate, undo, redo, and save PDF-native bookmarks and text highlights from the Clarix workspace.

## Architecture

Clarix keeps a per-open-document edit session populated from the opened PDF's outline and highlight annotations. The session is the immediate rendering source and owns a command-based undo/redo history. The Rust PDF bridge converts that session into standard PDF outline entries and `/Highlight` annotations through `lopdf`; Save atomically writes the original file and reloads it. No bookmark or highlight state is persisted as Clarix-only document metadata.

## Interaction model

- The title bar starts with Save, Undo, and Redo. Save is enabled only while the active document is dirty. Undo and Redo reflect their respective history stacks. Keyboard shortcuts are `Ctrl+S`, `Ctrl+Z`, and `Ctrl+Shift+Z`.
- The left workspace sidebar gets a Bookmarks pane. It lists active-document PDF outlines, permits an Add bookmark action at the current page, supports inline rename, and navigates to the outline destination when clicked.
- Text selection opens a context menu containing Copy, Bookmark, preset highlight colours, and a More colours action. Copy uses Flutter's clipboard API.
- Highlight overlays are hit-testable. Selecting one opens an editor for changing its colour or removing it.
- The colour inspector can remain docked in the reader's right-side utility region. It has preset swatches and a hue/saturation/value picker that produces an exact ARGB colour.
- Closing a dirty tab or application opens a confirmation dialog: Save, Discard, or Cancel. Save failures keep the document open and dirty.

## PDF format and save behavior

- Bookmarks are emitted as standard PDF `/Outlines` entries with a named title and an `/XYZ` destination for the stored page/view coordinates.
- Highlights are emitted as standard `/Annot` dictionaries with `/Subtype /Highlight`, `/Rect`, `/QuadPoints`, `/C`, `/CA`, and the selected text as `/Contents`.
- Existing bookmark/highlight data is read from the opened PDF. At Save, Clarix replaces only the outline and Clarix-managed annotation structures, retaining all unrelated PDF objects. Saving uses a sibling temporary path then atomically replaces the original where the platform permits.
- The source PDF must be writable and not encrypted in a way that prevents modification. The UI reports a clear save error and leaves the edit session dirty if it is not.

## State and history

`PdfEditSession` holds bookmarks, highlights, selected annotation id, custom colour, and a `PdfEditHistory`. History commands hold forward and inverse operations rather than document snapshots. Creating, renaming, recolouring, or deleting a bookmark/highlight pushes one command; undo moves it to redo, and a new edit clears redo. View navigation and text selection do not create history entries.

## Testing

- Dart unit tests cover dirty transitions, command undo/redo, redo invalidation, and colour updates.
- Rust tests cover PDF outline/highlight serialization and loading standard objects.
- Widget tests cover title-bar enabled states and keyboard shortcuts, bookmark navigation/rename, selection context commands, and dirty-close confirmation.
- `flutter test`, `flutter analyze`, and `cargo test` verify the feature.
