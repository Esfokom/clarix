# Right tool-window rail design

## Goal

Replace the competing Document inspector and Clarix AI right panes with an IDE-style vertical tool-window rail.

## Behavior

A fixed 40 px vertical rail stays on the far right of the desktop workspace. It contains Document inspector and Clarix AI icons. Selecting an inactive icon opens its pane at the persisted right-pane width. Selecting the active icon closes the pane and leaves only the rail visible. Only one right tool window can be open at a time.

On narrow layouts, the existing AI overlay remains the fallback. The rail does not reopen documents or alter reader state.

## State and tests

Persist an enum-like selected/closed right tool-window state in `WorkspaceSession`. Tests cover rail selection, active-icon close behavior, mutual exclusion, session migration, and narrow-layout fallback.
