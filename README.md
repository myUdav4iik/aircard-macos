# AirCard macOS

Native macOS port of the Apple Wallet card customization flow from [AirCard-Windows](https://github.com/Lumid-Off/AirCard-Windows). The UI and orchestration are written in Swift 6.2 and use Swift Concurrency for iPhone detection, image preparation, and atomic writes.

> Status: tested with iPhone18,3 on iOS 27.2 (build 24B5084k). Card hash detection also supports iOS 18 (including 18.7.8). This project uses private Apple APIs and is experimental; it is not an official Apple tool.

## Language

The app now uses English for user-facing text.

## Run

From this folder:

```sh
chmod +x Scripts/build_helpers.sh
Scripts/build_helpers.sh
swift run
```

To build a universal app bundle you can open with double-click:

```sh
chmod +x Scripts/build_app.sh
Scripts/build_app.sh
open build/AirCardMac.app
```

To also build a `.dmg` installer:

```sh
chmod +x Scripts/build_dmg.sh
Scripts/build_dmg.sh
open build/AirCardMac.dmg
```

The DMG includes the universal `AirCardMac.app` for Apple Silicon and Intel.

Connect a paired iPhone over USB, unlock it, and tap “Trust”. Open Apple Books once before the first flash. Click “Detect from Wallet”, open Apple Wallet, and tap a card. The card appears in the list, can auto-link (with “Follow the last card I open” enabled), and is saved for next time. You can rename, copy, or forget each card, or paste a hash manually. Then choose an image, optionally add transparent PNG overlays, and click “Apply Skin”.

The flow preserves/restores temporary Books files and cleans generated artifacts. Only assets for the selected card are written, and cache invalidation is attempted.

## Card Studio

The app is organized in a sidebar: iPhone, Card Studio, Passcode Keyboard, detected cards, and Activity.

The studio uses a layer document (`.aircardskin`) rendered with Core Image and runtime-compiled Metal shaders (no Xcode or Metal Toolchain required). The same pipeline generates preview and files written to Wallet.

- Layers: image, color, linear/radial/conic gradient, mesh gradient, holographic, brushed metal, sheen, grain, pattern (lines, dots, grid, carbon fiber, guilloche, waves), and text.
- Each layer supports opacity and blend mode (multiply, screen, overlay, soft light, color dodge, etc.), plus global color/vignette/bloom/blur/sharpen adjustments.
- Built-in styles: Titanium, Holo, Aurora, Carbon, Guilloche, Glass, Sunset, and Noir.
- Drag the card to tilt and preview reflective effects. Wallet receives a static image, so “Tilt” chooses the frozen export angle.
- “Wallet Zones” marks the approximate strip visible in the Wallet card stack.
- Undo/redo, save/open `.aircardskin`, and drag-and-drop image import are supported.
- Applied skins are saved in `~/Library/Application Support/AirCard/Cards/<hash>/` with thumbnail, 11 Wallet files, `.aircardskin`, and original images.

## Current Scope

- Initial functional Wallet card skin port.
- Native paired-iPhone detection.
- Syslog hash detection compatible with iOS 18 (NUL-separated records, split lines across reads, `Passes/Cards/...` and `uniqueID = ...` paths), with false-positive filtering.
- Persistent detected-card list (name, last seen, one-click selection).
- Artwork preparation at 1536×969 and 1024×646 PNG plus PDF.
- Multiple transparent PNG overlays with ordering and preview.
- Batch flash plus Books cleanup/restore.
- Apple Pay artwork writes via canonical names (`cardBackgroundCombined`, `diffuse`, `background`, `strip`) in 3x, 2x, and PDF.
- `.passthm` recolor/flash support for TelephonyUI-8/9/10, including `--white`, `--black`, `--white-bold`, and `--black-bold` variants.
- Keyboard language naming support (English, Russian, Ukrainian, Japanese, Universal) and `_big` marker handling for iOS 16–18.
- Automatic cache target: iOS 18+ → `TelephonyUI-10`, iOS 16–17 → `TelephonyUI-9`, older → `TelephonyUI-8`.
- AirTraffic timeout `max(60, files × 2)` seconds, with clearer error for locked iPhone.
- Asset download paths: “Download Assets…” and “Download .passthm…”.

## Limitations

- **You cannot read a card’s current Wallet artwork.** AFC exposes only `/var/mobile/Media`; Wallet card data (`/var/mobile/Library/Passes/Cards/...`) is outside that scope, and AirTraffic supports writing only.
- Because of that, **there is no backup of the original Apple/issuer design** and no true live thumbnail of each card. “Download Assets…” saves only what you selected and what the app wrote.
- To restore the original design, remove the card from Wallet and add it again.
- Motion/gyro effects are drawn by iOS; the written artwork remains static.

## About Number Color

The original repository also supports `.passthm` keypad packages for iOS passcode UI. Digits are not recolorable text; they are rasterized images copied into `TelephonyUI` caches with names like:

```text
en-2-A B C--white.png
en-2-A B C--white-bold.png
```

So changing number color means recoloring/regenerating key PNGs and writing matching variants under `/var/mobile/Library/Caches/TelephonyUI-10` (or `-9` / `-8`, depending on iOS). The `-bold` variant is used when “Bold Text” is enabled.

In the app: choose a `.passthm`, select color, verify preview, and click “Apply keyboard color”. The macOS port preserves package naming/variants, converts JPG/JPEG to PNG, and writes in batches with single-file fallback. Then lock the iPhone so TelephonyUI reloads cache.

For Apple Pay cards, iOS generally decides number color internally. This build also writes canonical assets (`diffuse`, `background`, `strip`) in addition to `cardBackgroundCombined`, matching related iOS-port behavior.

The app also includes an experimental path for number text color: it reads `pass.json` and attempts to change only `foregroundColor`.
