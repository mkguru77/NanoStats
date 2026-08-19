# NanoStats

Lightweight, zero-dependency macOS menu-bar system monitor (SwiftPM,
single target `NanoStats`, macOS 11+).

## Commands
- `swift build` — dev build; binary at `.build/debug/NanoStats`
- `swift run` — runs bare binary (no Info.plist, no Dock icon suppression)
- `./build_app.sh` — full `.app` bundle + icons (preferred for manual testing)
- `swift build -c release` — optimized build
- Tag `v*` triggers `.github/workflows/release.yml`
  (bundle → DMG → GitHub Release)

## Architecture
Entry: `Sources/NanoStats/main.swift` → `StatusBarController` (menu bar hub:
Timer polling, UserDefaults prefs `UnitMode`, `RefreshInterval`,
`SelectedInterface`, `EnabledMetrics`, `MetricOrder`, menus, launch-at-login).
Pollers: `NetworkMonitor` (getifaddrs), `SystemMonitor`
(host_statistics64 CPU/RAM, IOKit GPU, thermal).
Rendering: `IconProvider.renderMetricsImage` draws stacked metric blocks;
`SpeedFormatter` formats rates.
UI: `ReorderPanel` (drag-reorder), menu actions in `StatusBarController`.

## Gotchas
- **Temperature is read from real die sensors on Apple Silicon** via the private
  `IOHIDEventSystemClient` API (no root needed); falls back to an ESTIMATE from
  `ProcessInfo.thermalState` when sensors are unavailable (Nominal=42, Fair=58,
  Serious=75, Critical=92 °C).
- Sampling runs on a private serial queue in `StatusBarController`;
  keep monitor state off the main thread.
- Network `auto` mode sums all `en*/utun*` interfaces;
  manual mode polls one interface.
- App runs as `LSUIElement` menu-bar accessory (no Dock icon).
- Launch-at-login: `SMAppService` on macOS 13+,
  UserDefaults fallback below.
