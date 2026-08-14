# Custom Window Chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Clarix a frameless, rounded, reference-matched Windows title bar with custom controls and workspace actions.

**Architecture:** Configure `bitsdojo_window` in the Windows runner, then place a reusable `DesktopWindowChrome` above the workspace. Keep `window_manager` for existing close confirmation and lifecycle only; it no longer configures a normal title bar.

**Tech Stack:** Flutter, `bitsdojo_window`, `window_manager`, Google Fonts, Flutter widget tests, Windows C++ runner.

## Global Constraints

- Use `bitsdojo_window` for the custom frame, drag area, resize behavior, and minimize/maximize/close controls.
- Keep `window_manager` only for initial sizing/showing and close/session-discard confirmation.
- Use 48 px `#2F2F2F` chrome, `#3A3A3A` search surface, `#A6A6A6` utility icons/text, and Roboto for chrome text.
- The search field is presentation-only; both import controls invoke the current PDF picker.
- Settings is exposed through the chrome menu.
- Do not run `flutter_rust_bridge_codegen generate`; bridge APIs are unchanged.

---

### Task 1: Configure the native custom frame

**Files:**
- Modify: `pubspec.yaml`
- Modify: `windows/runner/main.cpp`
- Modify: `lib/src/app.dart`

**Interfaces:**
- Produces: Windows custom frame setup before `FlutterWindow` construction.

- [ ] **Step 1: Add the dependency**

Run `flutter pub add bitsdojo_window`, then confirm `pubspec.yaml` and `pubspec.lock` include the package.

- [ ] **Step 2: Configure the Windows runner**

Add this header and configuration before the app window is created:

```cpp
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>

auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
```

- [ ] **Step 3: Remove normal title-bar configuration**

Remove `titleBarStyle: TitleBarStyle.normal` from `_WindowBootstrap` while retaining size, minimum size, centering, show, and focus behavior.

- [ ] **Step 4: Verify and commit**

Run `flutter pub get` and `flutter analyze lib/src/app.dart`. Then commit:

```powershell
git add pubspec.yaml pubspec.lock windows/runner/main.cpp lib/src/app.dart
git commit -m "feat: enable custom desktop window frame"
```

### Task 2: Create the reusable desktop chrome

**Files:**
- Create: `lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart`
- Create: `test/workspace_ai/desktop_window_chrome_test.dart`

**Interfaces:**
- Produces: `DesktopWindowChrome({required Widget child, required VoidCallback onImport, required VoidCallback onOpenSettings})`.

- [ ] **Step 1: Write a failing layout and action test**

Pump `DesktopWindowChrome` around a keyed body. Assert keys `desktop-window-chrome`, `chrome-search-field`, `chrome-import`, `chrome-scan-import`, `chrome-overflow`, `chrome-menu`, `chrome-minimize`, `chrome-maximize`, and `chrome-close`. Tap both import actions and expect two callback invocations. Open the menu and verify its Settings item calls `onOpenSettings`.

- [ ] **Step 2: Verify the test fails**

Run `flutter test test/workspace_ai/desktop_window_chrome_test.dart`.

Expected: FAIL because `DesktopWindowChrome` does not exist.

- [ ] **Step 3: Implement the chrome widget**

Create a column whose first child is a 48 px `WindowTitleBarBox` with rounded 12 px top corners and `#2F2F2F` fill. Add a left `ConstrainedBox(maxWidth: 660)` `#3A3A3A` search shell with search, add/import, and scan/import controls. Use `GoogleFonts.roboto` at 16 px for `Search Books…`.

Use `Expanded(child: MoveWindow())` for the center drag zone. Render separate overflow and menu glyphs, a `PopupMenuButton` Settings action, and custom-colored `MinimizeWindowButton`, `MaximizeWindowButton`, and `CloseWindowButton` controls.

- [ ] **Step 4: Verify and commit**

Run:

```powershell
dart format lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart test/workspace_ai/desktop_window_chrome_test.dart
flutter test test/workspace_ai/desktop_window_chrome_test.dart
```

Commit:

```powershell
git add lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart test/workspace_ai/desktop_window_chrome_test.dart
git commit -m "feat: add custom desktop window chrome"
```

### Task 3: Wire chrome to the workspace

**Files:**
- Modify: `lib/src/features/workspace/presentation/screens/workspace_screen.dart`
- Modify: `test/workspace_ai/desktop_window_chrome_test.dart`

**Interfaces:**
- Consumes: `DesktopWindowChrome`, `WorkspaceNotifier.pickAndOpenPdf()`, and `showAppSettingsDialog`.
- Produces: workspace content below the title bar with existing import and Settings actions.

- [ ] **Step 1: Wrap the workspace scaffold**

Return `DesktopWindowChrome(child: scaffold, onImport: ..., onOpenSettings: ...)` from `WorkspaceScreen.build`. Set `onImport` to `ref.read(workspaceNotifierProvider.notifier).pickAndOpenPdf` and Settings to `showAppSettingsDialog(context)`.

- [ ] **Step 2: Extend the test for placement**

Assert the body’s `tester.getTopLeft` is below the chrome and the Settings menu callback remains available after integration.

- [ ] **Step 3: Verify and commit**

Run `flutter test test/workspace_ai/desktop_window_chrome_test.dart` and `flutter analyze lib/src/features/workspace/presentation/screens/workspace_screen.dart lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart`.

```powershell
git add lib/src/features/workspace/presentation/screens/workspace_screen.dart test/workspace_ai/desktop_window_chrome_test.dart
git commit -m "feat: place workspace beneath custom window chrome"
```

### Task 4: Full verification

**Files:**
- Verify: `windows/runner/main.cpp`
- Verify: `lib/src/features/workspace/presentation/widgets/desktop_window_chrome.dart`

- [ ] **Step 1: Run full checks**

Run `flutter analyze` and `flutter test`; both must pass.

- [ ] **Step 2: Manually validate Windows**

Run `flutter run -d windows`. Verify rounded custom corners, draggable center, all window controls, Settings menu, both import buttons, and the existing close confirmation.

- [ ] **Step 3: Inspect scope**

Run `git diff --check` and `git status --short`; preserve pre-existing untracked planning notes.
