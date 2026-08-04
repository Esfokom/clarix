# Custom Window Chrome Design

## Goal

Replace Clarix’s native Windows title bar and black top edge with a frameless, rounded, book-library-style desktop chrome modeled on the supplied reference.

## Window integration

`bitsdojo_window` owns the custom Windows frame, draggable title area, native resize behavior, and minimize/maximize/close controls. The Windows runner enables `BDW_CUSTOM_FRAME` and `BDW_HIDE_ON_STARTUP`.

`window_manager` remains responsible only for current application lifecycle behavior: initial sizing/showing, close interception, and session-discard confirmation. It must not draw or configure the normal system title bar once the custom frame is active.

## Chrome layout

The Flutter workspace is enclosed by a rounded custom frame. Its 48 px top bar has rounded top corners and uses `#2F2F2F`; the workspace content remains below it.

- Left: a 660 px maximum rounded search field in `#3A3A3A`, with search icon, `Search Books…` placeholder, divider, add/import action, and scan/import action.
- Center: the remaining strip is a `MoveWindow` drag target.
- Right: overflow action, menu action, then a compact window-control group for minimize, maximize/restore, and close.
- Settings moves from the workspace sidebar header into the overflow/menu surface, avoiding a competing top-bar control.

The chrome uses Roboto at 16 px for the search placeholder and 14 px for utility/menu text, with muted `#A6A6A6` icons. The main workspace retains its existing theme and typography.

## Interaction

The search field receives focus but is initially presentation-only; it must not claim a document-search feature. The add/import action invokes the existing document import entry point. The scan/import action may share that import action until a separate scanner capability exists. The overflow/menu exposes Settings.

`MinimizeWindowButton`, `MaximizeWindowButton`, and `CloseWindowButton` receive custom neutral and close-hover colors. Native window close events still route through the existing confirmation logic.

## Tests

Widget coverage verifies the custom chrome layout, Settings access through the menu, and that the workspace is placed beneath the top bar. Platform setup is verified by inspecting Windows runner configuration and by launching the Windows target manually after code generation/dependency installation.
