# Satus Verification Protocol

## 1. Setup & Installation
- [ ] **Clean Install**: Delete `~/Applications/Satus.app` and run `./bundle_app.sh --clean` to build fresh.
- [ ] **Launch**: Open Satus from the Applications folder. Verify it launches and prompts for permissions if needed.
- [ ] **Dock Icon**: Verify the Satus icon appears in the Dock.

## 2. Window Management (Critical)
- [ ] **Close Window**: Click the Red 'X' or press `CMD+W`.
    - *Expected*: Window disappears, App remains running (Dot in Dock).
- [ ] **Re-open via Menu**: Go to Menu Bar -> `Window` -> `Open Satus` (or press `CMD+0`).
    - *Expected*: Main window reappears.
- [ ] **Re-open via Dock**: Click the Satus icon in the Dock.
    - *Expected*: Main window reappears.

## 3. Navigation & Focus
- [ ] **Initial Focus**: Launch app.
    - *Expected*: Sidebar "All Apps" is selected/highlighted by default.
- [ ] **Sidebar Navigation**: Use Up/Down arrow keys.
    - *Expected*: Selection moves between All Apps, Open Apps, Tags, etc.
- [ ] **Switch to Grid**: Press Right Arrow from Sidebar.
    - *Expected*: Focus moves to the first app in the grid.
- [ ] **Grid Navigation**: Use Arrow keys (Up/Down/Left/Right).
    - *Expected*: Focus moves between app icons.
- [ ] **Return to Sidebar**: Press Left Arrow when on the leftmost column.
    - *Expected*: Focus returns to the active Sidebar Item.
- [ ] **Search Interaction**:
    - Click `Search` box -> Type "Sa" -> Verify filtering.
    - Press `Esc` or Click Sidebar -> Verify search clears/loses focus and Arrows control Sidebar/Grid again.
    - *Regression Check*: Click Search, then click away. Press Down Arrow. Focus should NOT be stuck in search.

## 4. Key Features
### Open Apps & Switcher
- [ ] **View Open Apps**: Click "Open Apps" in Sidebar.
- [ ] **Hide App**: Right-click a running app (e.g., Chrome) -> Select `Hide`.
    - *Expected*: App disappears from "Open Apps" list.
- [ ] **Persistence Check**:
    - Quit the target app (Chrome) and relaunch it.
    - *Expected*: It should *NOT* reappear in "Open Apps" (it is persistently hidden).
    - Quit Satus and Relaunch Satus.
    - *Expected*: App remains hidden.
- [ ] **Unhide App**: Drag the app from Finder/Dock onto the Satus window OR use the "Hidden Apps" section if visible (at bottom of Open Apps list).
    - Or: Locate in "All Apps", Right-click -> `Content Menu` -> `Restore to Open Apps` (if verified implemented) or `Unhide`.

### Tags
- [ ] **Create Tag**: Click "Add New Tag...". Name it "Test Tag".
- [ ] **Assign Tag**: Drag an app onto "Test Tag" or Right-click App -> Tags -> "Test Tag".
- [ ] **Filter**: Click "Test Tag" in side bar. Verify app appears.
- [ ] **Remove Tag**: Right-click "Test Tag" in sidebar -> "Remove Tag". Verify tag disappears.

## 5. Settings
- [ ] **Access**: Click Gear icon.
- [ ] **Appearance**: Change Theme (Dark/Light). Verify update.
- [ ] **Icon Size**: Adjust slider. Verify grid icons resize.
- [ ] **Layout**: Switch List/Grid view.
- [ ] **Shortcuts**: Verify assigned shortcuts work (e.g. `CMD+2` for Open Apps).

## 6. App Review Compliance
- [ ] **About Panel**: Menu -> Satus -> About Satus.
    - *Expected*: Shows Version 1.1, No Build Number, Copyright 2026.
- [ ] **Help**: Menu -> Help -> Satus Help.
    - *Expected*: Help window opens.

## 7. Performance
- [ ] **Responsiveness**: App should feel snappy. No lags on scrolling or typing.
