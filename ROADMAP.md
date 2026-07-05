# VideoMaster Roadmap

This document captures the high-level vision and major phases for VideoMaster. Detailed feature and improvement ideas are captured here (under the relevant Phase) or in `AI-IMPROVEMENTS.md`. (Older separate files `IMPROVEMENTS.md` and `DEVELOPMENT_SUMMARY.md` have been retired into this roadmap.)

## Vision

A fast, native macOS app that lets people **find, organize, and enjoy** their personal video libraries — without forcing them to move files into a proprietary container.

Key qualities:
- Excellent performance even with thousands of videos
- Deep macOS integration and keyboard-driven workflow
- Respect for the user's existing folder structure
- High-quality inline playback + useful organization tools (ratings, tags, collections, custom metadata)

## Current State (as of v0.28.0)

**Core experience is solid and considerably deepened since v0.13**:
- **Curated Wall**: unified grid + Inspector + collapsible, responsive filters drawer (Smart Libraries, Collections, Rating/Duration, Tags), replacing the old nav-bar/detail-pane split; wall and drawer regions are user-resizable and persist their size
- **Unified playback engine**: one resizable floating player (Compact / Windowed / Full screen) backed by a single shared `InlinePlaybackController`; true full-screen carry-across (no restart); resume positions with a visible "continue watching" progress bar on grid cards; sidecar subtitle support; Play / Play-from-Beginning
- **Collections** (rule-based smart folders) now support **two-level AND/OR grouping** — rules cluster into groups (ALL/ANY within a group), groups combine via an outer ALL/ANY toggle, e.g. `(Tag=Vacation AND Rating≥4) OR Tag=Favorite`
- **Duplicates smart library** rebuilt on content fingerprinting (SHA-256 of file size + first/last bytes) instead of size+duration heuristics, with background backfill + progress and sticky per-pair "Not a Duplicate" marking
- **Re-encode queue**: crash-safe MP4 conversion (temp file + kept backup, promoted only on success), full queue manager (abort / reorder / restore / retry), persists across relaunch
- **Move queue**: crash-safe cross-volume moves (temp + size-verify + promote before deleting source), queue manager, per-video UI lockout while a move is in flight
- **Tags**: standalone creation, rename/delete from the filters drawer, stable (non-reshuffling) assignment list, live per-tag counts
- **Custom metadata** fields integrated into sort menu and List View columns (typed comparators, no per-row parsing)
- **Thumbnail tools**: Regenerate Thumbnail, Make Thumbnail from Current Frame, Modify Filmstrip…
- **Keyboard-driven workflow**: Home/End (go to first/last), arrow-key grid navigation, a rationalized app-wide modifier scheme (⌃ = OS fullscreen only, ⌥ = alternate action, ⇧ = reveals/adds UI), ⌘F search focus
- Smart libraries for Missing (filesystem check, with a manual rescan affordance) and Corrupt (computed live from in-library metadata, plus an automatic per-selection recheck) files
- Drag-and-drop import (files and folders) onto the main window

**Known architectural strengths**:
- Careful performance work around SwiftUI diffing and large datasets (compiled-predicate rule matching, off-main filter/count computation, os_signpost instrumentation)
- Clean separation via ViewModel + Repository pattern, GRDB-backed persistence with sequential migrations
- Layout persistence that handles browsing vs. playback modes

## Path to v1.0

The current state (v0.28.0, `feature/curated-wall`) is the **v1.0 candidate**, pending a deliberate readiness pass rather than new features. That pass covers:

1. **Regression test suite** — no automated tests exist today (`project.yml` has no test target). Priority is ViewModel + Repository logic coverage (filtering, collections matching, migrations, duplicates) since it's testable without driving the GUI; full UI automation (XCUITest) is a separate, higher-effort tier.
2. **Performance audit** — reusing the `os_signpost`/unified-log instrumentation approach already established this cycle; validate behavior at large library sizes (10k+ videos).
3. **Feature audit against this roadmap** — confirm what's actually shipped and working matches what's documented here, and flag anything half-finished.
4. **Code review** — a full-branch pass (e.g. `/code-review ultra`) before calling the branch done.
5. **Security audit** — scoped to what's actually relevant for a local-only, unsandboxed (`app-sandbox: false`) file browser/player: filesystem-handling safety (path handling, no injection in `Process`/ffmpeg invocations), safe import/move/re-encode error paths — not a general web-app checklist.

Only after this pass should sandboxing/distribution (Phase 4 below) be seriously scoped.

## Major Themes / Phases (High Level)

### Phase 0 — Foundations (complete)
- Core browsing, metadata, playback, scanning
- Performance baseline
- Build / release discipline

### Phase 1 — Polish & Reliability (substantially complete)
- Curated Wall redesign, unified playback engine, Duplicates rework, and Collections grouping (above) closed out the major known UX friction and reliability gaps from this phase
- Remaining polish surfaces primarily through the v1.0 readiness pass above, not a fixed backlog

### Phase 2 — Power User & Organization Features
- Advanced search (beyond filename FTS5)
- Batch operations and multi-select power features
- Import / library management improvements (auto-import from data sources?)
- Further organization tools (notes, auto-tagging ideas)

### Phase 3 — AI Augmentation (exploratory)
- See `AI-IMPROVEMENTS.md`
- Potential areas: semantic search, smart tagging, content-aware suggestions, duplicate detection

### Phase 4 — Distribution & Longevity
- Proper app sandboxing (if/when feasible) — currently unsandboxed
- Distribution story (TestFlight / direct / Mac App Store?)
- Long-term maintainability and documentation
- Full user + developer documentation (web-based) when closer to public release

## Guiding Principles

1. **Performance is a feature.** Large libraries must feel responsive.
2. **Native first.** Leverage SwiftUI + AppKit where it makes the experience better, not just "web-like".
3. **Respect the filesystem.** The app indexes and enhances; it does not own the user's files.
4. **Keyboard and efficiency matter.** Many users will have hundreds or thousands of clips.
5. **Incremental, high-quality releases.** Prefer shipping small, solid improvements over big risky ones.

## How to Use This Document

- When starting a large body of work, check here first.
- Update this file when major themes shift or new phases are defined.
- Keep detailed task lists here (under the appropriate Phase) or in GitHub issues.

---

*Last significant update: v0.28.0 (2026-07-04) — refreshed to reflect Curated Wall, unified playback, Duplicates rework, and Collections grouping; added the v1.0 readiness pass.*