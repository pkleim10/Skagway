# VideoMaster

A native macOS app for browsing, organizing, and playing personal video libraries — without moving files into a proprietary container.

VideoMaster indexes folders you already have on disk, then adds ratings, tags, smart collections, custom metadata, and fast keyboard-driven browsing on top.

**Current version:** see `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in [`project.yml`](project.yml) (also reflected in [`CHANGELOG.md`](CHANGELOG.md)).

---

## Highlights

- **Grid + List browsing** with a focused Inspector for the selected video
- **Quick Filter** and **Advanced Filter** (boolean rules) sharing one engine with **Collections**
- **Smart libraries** (e.g. Missing, Corrupt, Duplicates) plus rule-based Collections with AND/OR groups
- **Inline playback** — resizable floating player (Compact / Windowed / Full screen), resume positions, sidecar subtitles
- **Tags, ratings, custom metadata**, sort, shuffle, Surprise Me
- **Import / scan** from watched folders; drag-and-drop files and folders
- **Export Metadata** (CSV or JSON Lines) for the filtered set or selection, with a field picker
- **Re-encode** and **cross-volume move** queues with crash-safe temp → promote workflows
- **Dark-only** cinematic UI tuned for media work
- Built for **large libraries** (thousands of videos) with careful SwiftUI and filtering performance

Files stay where you put them. VideoMaster indexes and enhances; it does not own your media.

---

## Requirements

| Item | Notes |
|------|--------|
| **macOS** | 26.0+ (Tahoe) |
| **Xcode** | Current toolchain with Swift 5 language mode (`SWIFT_VERSION: "5"` in `project.yml`) |
| **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** | Regenerates `VideoMaster.xcodeproj` from `project.yml` |
| **ffmpeg** (optional) | Required only for re-encode; path configurable in Settings → Tools |

The app is **not sandboxed** (`VideoMaster.entitlements`) so it can browse arbitrary folders and run tools like ffmpeg. Treat that as intentional for a local library manager, not a shipping App Store configuration yet.

---

## Build & install

The canonical day-to-day path:

```bash
bash scripts/build_and_install.sh
```

That script:

1. Bumps `CURRENT_PROJECT_VERSION` in `project.yml` (unless `--no-bump`)
2. Runs `xcodegen generate`
3. Builds **Release** by default
4. Installs to `/Applications/VideoMaster.app`

Useful flags:

```bash
bash scripts/build_and_install.sh --debug      # Debug configuration
bash scripts/build_and_install.sh --no-bump    # Retry without incrementing build
bash scripts/build_and_install.sh --no-install # Build only
```

**Note:** `scripts/build_and_install.sh` may point at a machine-specific `DEVELOPER_DIR` for Xcode. Adjust that path if your Xcode install lives elsewhere.

Manual alternative:

```bash
brew install xcodegen   # if needed
xcodegen generate
open VideoMaster.xcodeproj
# Build & run the VideoMaster scheme from Xcode
```

---

## Project layout

```
VideoMaster/
├── project.yml              # XcodeGen project + version numbers
├── scripts/
│   └── build_and_install.sh # Canonical build / install
├── VideoMaster/             # App sources
│   ├── App/                 # App entry, AppState
│   ├── Views/               # SwiftUI UI (library, inspector, filters, player, settings)
│   ├── ViewModels/          # LibraryViewModel (primary state)
│   ├── Models/              # Domain types, filters, layout, collections
│   ├── Services/            # Scanning, thumbnails, ffmpeg, etc.
│   ├── Database/            # GRDB setup + migrations
│   └── Design/              # Design tokens / component styles
├── CHANGELOG.md             # Live Unreleased + shipped releases
├── ROADMAP.md               # Vision and phases
├── AGENTS.md                # Contract for AI agents working in this repo
└── SKILLS.md                # Recommended skills / subagents
```

Architecture is **MVVM + repository**, with **GRDB.swift** (SQLite) for persistence and **AVFoundation** for thumbnails and playback.

Important convention: pass `LibraryViewModel` and `ThumbnailService` as **explicit parameters** into child views. Do not rely on `@Environment` through `Table` / `Menu` / `NavigationSplitView` on macOS — those often render in isolated contexts.

---

## Versioning & releases

| Field | Meaning |
|-------|---------|
| `MARKETING_VERSION` | User-facing version (e.g. `0.34.0`) — change only on intentional releases |
| `CURRENT_PROJECT_VERSION` | Build number — incremented by the build script on each install |

Release history and Unreleased notes live in [`CHANGELOG.md`](CHANGELOG.md). High-level direction is in [`ROADMAP.md`](ROADMAP.md). Agent/release workflow details are in [`AGENTS.md`](AGENTS.md) and `.cursor/rules/`.

---

## Documentation

| Doc | Purpose |
|-----|---------|
| [`ROADMAP.md`](ROADMAP.md) | Vision, phases, path to v1.0 |
| [`CHANGELOG.md`](CHANGELOG.md) | What shipped (and what’s Unreleased) |
| [`AGENTS.md`](AGENTS.md) | How agents should build, commit, and release |
| [`SKILLS.md`](SKILLS.md) | Skills / subagent guidance |
| [`GRID-PERFORMANCE.md`](GRID-PERFORMANCE.md) | Grid / filtering performance notes |
| [`VideoMaster/Design/README.md`](VideoMaster/Design/README.md) | Design system (dark cinematic blue) |

A full end-user guide is intentionally light for now; use the in-app UI, menus, and Settings day to day. Broader user docs are planned closer to a public release.

---

## Status

VideoMaster is under active development toward a **v1.0** readiness pass (regression coverage, performance audit, polish). It is a personal / local library tool first — not yet a sandboxed Mac App Store product.

---

## License

Proprietary / all rights reserved unless a license file is added to this repository.
