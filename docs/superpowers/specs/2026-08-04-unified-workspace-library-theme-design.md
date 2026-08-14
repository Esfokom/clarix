# Unified Workspace Library Theme Design

## Goal

Extend Clarix’s warm ash, Roboto library aesthetic from the start surface into loaded-PDF workspace and AI chat, while giving document search one consistent title-bar entry point.

## Search

The title-bar `Search PDFs…` field searches only currently open PDFs using the existing workspace search behavior. Results identify document and page and navigate to the selected open tab/page. The duplicate document-local search input and controls are removed.

## Theme

Shared workspace tokens use ash-gray canvas/panel surfaces and Roboto typography. A small central type scale defines display titles, section labels, body, captions, controls, and chat Markdown. PDF pages retain their natural page canvas; all surrounding workspace chrome, AI pane, composer, controls, and response content use the shared library styling.

## AI

The AI pane uses the same ash surfaces and Roboto type classes. Assistant Markdown and citations preserve their semantic hierarchy, math support, and document navigation while inheriting the centralized body/caption styles.

## Tests

Widget tests cover title-bar search integration and shared theme application; existing AI Markdown/search/navigation tests remain green.
