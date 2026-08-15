# Building NanoStats

This document provides instructions for compiling, packaging, and building **NanoStats**, a lightweight macOS menu bar app written in Swift.

---

## Prerequisites

Before building, ensure your environment meets the following requirements:

- **Operating System:** macOS 11.0 (Big Sur) or later
- **Architecture:** Apple Silicon (`arm64`)
- **Build Tools:** Xcode Command Line Tools (includes `swiftc`, `sips`, `iconutil`, and `hdiutil`)

If you do not have Xcode Command Line Tools installed, run:

```bash
xcode-select --install
```

---

## 1. Build Native macOS App Bundle (Recommended)

The recommended way to build NanoStats is using the included [`build_app.sh`](build_app.sh) script. This script compiles all Swift sources with optimizations, creates the `NanoStats.app` bundle, generates the proper `Info.plist` (configuring `LSUIElement` so the app runs purely in the menu bar without a Dock icon), and converts `assets/app-icon.png` into `AppIcon.icns`.

### Steps:

1. **Make the script executable:**

   ```bash
   chmod +x build_app.sh
   ```

2. **Run the build script:**

   ```bash
   ./build_app.sh
   ```

3. **Verify the output:**

   After a successful build, a `NanoStats.app` bundle will be generated in the project root directory.

4. **Run the App:**

   ```bash
   open NanoStats.app
   ```

---

## 2. Creating a DMG Disk Image

To create a standalone `.dmg` installer for distribution:

1. Build the app bundle first:
   ```bash
   ./build_app.sh
   ```

2. Generate the DMG image using `hdiutil`:
   ```bash
   hdiutil create -volname "NanoStats" -srcfolder NanoStats.app -ov -format UDZO NanoStats.dmg
   ```

This will produce `NanoStats.dmg` in your project directory.

---

## 3. Building with Swift Package Manager (Development)

NanoStats includes a [`Package.swift`](Package.swift) for development and quick compilation via Swift Package Manager (SPM).

### Debug Build:
```bash
swift build
```
The executable will be located at `.build/debug/NanoStats`.

### Release Build:
```bash
swift build -c release
```
The executable will be located at `.build/release/NanoStats`.

### Run Directly:
```bash
swift run
```

> **Note:** Running via `swift run` executes the raw Swift binary directly. It will run in your menu bar, but will not use the customized `Info.plist` or app icons bundled in `NanoStats.app`. Use `./build_app.sh` for full app bundle functionality.

---

## 4. Continuous Integration / GitHub Actions

Automated builds and release packaging are configured via GitHub Actions in [`.github/workflows/release.yml`](.github/workflows/release.yml).

When a git tag matching `v*` (e.g. `v1.0.0`) is pushed, GitHub Actions will:
1. Run `./build_app.sh` on a `macos-latest` runner.
2. Package `NanoStats.app` into `NanoStats.dmg`.
3. Create a GitHub Release with the DMG attached.

---

## Troubleshooting & Gatekeeper Notes

- **Permission Denied when running `build_app.sh`:**
  Run `chmod +x build_app.sh` to grant execution permissions.

- **Gatekeeper / Quarantine Attribute:**
  Because the app is not signed with an Apple Developer ID certificate, macOS Gatekeeper may block execution if downloaded from the web or unarchived. Remove the quarantine attribute if needed:
  ```bash
  xattr -d com.apple.quarantine NanoStats.app
  # or for DMG:
  xattr -d com.apple.quarantine NanoStats.dmg
  ```
