# Command Central

A do-everything command center for macOS — a tabbed dashboard, a menu-bar icon, and a global **⌥ Space** command palette, all in one native app.

Built with SwiftUI + AppKit and compiled with the plain Swift Package Manager — no Xcode project required.

## Features

- **⌥ Space palette** — summon it from anywhere. Launch apps, open sites, add tasks (`task buy milk`), save notes (`note idea…`), start a study stopwatch (`track maths`), set alarms (`alarm 7:30 wake up`), search Google/YouTube/Wikipedia, do inline math, toggle dark mode / Wi-Fi, lock the screen, and more. Add your own commands in the Commands tab.
- **Home** — a customizable widget grid: clock, tasks, weather, study stats, media controls, and friends.
- **Tracker** — study hours per subject with stopwatch and focus-timer logging, daily goals, streaks, and a 14-day chart.
- **Tasks & Notes** — quick capture from the palette, tagged by subject, with play-to-track integration.
- **Weather & Quakes** — current conditions, 12-hour rain outlook, sunrise/sunset, and severe-weather + earthquake alerts (Open-Meteo and USGS — no API keys needed).
- **Terminal** — a real zsh terminal embedded in a tab (via SwiftTerm), with a one-click Claude Code launcher.
- **Clocks & Alarms** — world clocks, alarms with notifications, and sleep tracking based on your Mac's sleep/wake events.
- **Windows / System / Clipboard / Media / Map / Calendar** — window overview across Spaces, CPU/RAM stats, clipboard history, media keys, quake map, and upcoming events.
- **13 tabs total** — reorder them, hide the ones you don't use, jump with ⌘1–⌘0.

## Requirements

- macOS 14 or later
- Swift toolchain (Xcode Command Line Tools are enough: `xcode-select --install`)

## Build & run

```sh
git clone https://github.com/Harshal-Mishra/CommandCentral.git
cd CommandCentral
./build.sh
open dist/CommandCentral.app
```

`build.sh` compiles a release binary and assembles `dist/CommandCentral.app` with an ad-hoc code signature, so it runs on your own Mac out of the box.

## Notes

- All your data stays local, stored as JSON in `~/Library/Application Support/CommandCentral/`. Nothing is sent anywhere.
- Window titles in the Windows tab need the Screen Recording permission; calendar events need Calendar access. Both are optional.
- Hotkey, tab layout, and other preferences live in the Settings tab.
