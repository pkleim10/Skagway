# Playback Modes — Expert Audit

**Date:** 2026-06-29
**Branch:** `feature/curated-wall`
**Scope:** The three inline-playback modes (Detail Pane, Overlay, Full Screen) and their interaction with the Curated Wall.
**Status:** Findings + redesign proposal for review. No code changed by this audit.

---

## TL;DR — Why playback feels shaky

The Curated Wall redesign **silently forked playback into three different engines with three different feature sets**, and left the original, full-featured engine wired to dead code:

| Mode | What actually runs in the Curated Wall | Feature completeness |
|------|----------------------------------------|----------------------|
| **Detail Pane** | `CuratedWallInspector.startLocalHeroPlayer()` — a bare `AVPlayer(url:).play()` | ❌ Minimal (regressed) |
| **Overlay** | `OverlayInlinePlayerView` | ✅ Full-featured |
| **Full Screen** | *Nothing dedicated* — falls through to the bare hero player | ❌ Broken |

The full-featured engine (`VideoDetailView`, 1597 lines: resume, subtitles, errors, fullscreen window, status monitoring) is **dead code** — it is only reachable through `libraryContent`, which has **zero references** in the Curated Wall `body`.

So the same video plays with different behavior depending on the mode, the most common path (Detail Pane) lost most of its features, and Full Screen doesn't open a fullscreen window at all. That inconsistency is the "shakiness."

---

## Current architecture (as built)

### State model — 3 modes derived from 2 booleans

`LibraryViewModel` represents playback with three loosely-coupled fields:

- `isPlayingInline: Bool` — "is something playing"
- `playInlineStartsFullscreen: Bool`
- `playInlineInOverlay: Bool`

Derived:
```
inlinePlaybackMode      = fullScreen if startsFullscreen
                          else overlay if inOverlay
                          else detailPane
inlineOverlayActive     = playInlineInOverlay && !playInlineStartsFullscreen
inlinePlaybackReshapesBrowser = isPlayingInline && mode == .detailPane
```

Mode switching (`setInlinePlaybackMode`) tears down by flipping `isPlayingInline = false`, mutates the two booleans, then **re-starts on the next runloop**:
```swift
if wasPlaying { isPlayingInline = false }
… mutate booleans …
if wasPlaying { DispatchQueue.main.async { self.isPlayingInline = true } }
```
This deferred re-entrancy is what couples teardown-in-one-view to startup-in-another. The code comments themselves flag the ordering hazard ("A mode switch sets `isPlayingInline = false` *after* flipping the mode booleans…").

### Who owns the AVPlayer

There are **three independent player owners**, each with its own `@State` AVPlayer and its own (or absent) lifecycle:

1. **`VideoDetailView`** (`Views/Detail/VideoDetailView.swift`) — `inlinePlayer`. Full engine: `isPlayable` preflight, resume-position load/save, resume banner + fade, sidecar subtitle discovery, `AVPlayerItem.status` monitoring + error overlay, `recordPlay`, Space/Shift-Space counters, **and the only creator of `FullscreenInlinePlayerWindowController`**. **DEAD CODE** (see below).
2. **`OverlayInlinePlayerView`** (`Views/Detail/OverlayInlinePlayerView.swift`) — `player`. Full engine *except* fullscreen routing (by design). Mounted by `OverlayPlayerPanel` in the Curated Wall overlay.
3. **`CuratedWallInspector`** (`Views/Inspector/CuratedWallInspector.swift`) — `heroPlayer`. **Bare**: `AVPlayer(url:)`, optional filmstrip seek, `play()`. Nothing else.

### Dead code confirmation

`grep` shows `libraryContent` is referenced **0 times**; `contentBody` / `libraryNavBar` only by `libraryContent`; `detailContent` only in a comment. The chain `libraryContent → contentBody/libraryNavBar → detailContent → VideoDetailView` is entirely unreachable from the live `body`, which renders the Curated Wall (`ResizableBrowserDetailSplitView` + `CuratedWallInspector`) directly.

Consequence: the **playback-mode segmented control also lives in the dead `libraryNavBar`**. In the Curated Wall the only ways to change mode are the ⌥⌘1/2/3 menu commands and the inspector's two buttons.

---

## Findings (by severity)

### 🔴 P1 — Full Screen mode is broken in the Curated Wall
`FullscreenInlinePlayerWindowController` is created **only** by the dead `VideoDetailView`. Selecting Full Screen (⌥⌘3) then playing satisfies `isDetailPlaying = isPlayingInline && !inlineOverlayActive` (true for fullscreen), so `CuratedWallInspector` just renders the hero player in the inspector pane. No borderless window, no menu-bar/Dock hiding, no Esc-to-close. Full Screen is effectively a broken alias of Detail Pane.

### 🔴 P1 — Detail-Pane playback regressed to a toy player
`startLocalHeroPlayer()` omits everything the engine used to do:
- **No resume position** (load *or* save). `stopHeroPlayer()` only `pause()` + `nil` — position is never persisted, so resume silently never works for the most common play path.
- **No resume banner.**
- **No sidecar subtitles** (no `SubtitleTrack`, no `.srt` discovery).
- **No unplayable/missing-file handling** (`isPlayable` preflight) and **no `AVPlayerItem.status` error overlay** — a bad file shows a blank/black hero with no feedback.
- **No `recordPlay`** → play counts and "Recently Played" are wrong for wall detail-pane plays.
- **No Space / Shift-Space**: the inspector does not observe `inlinePlayPauseToggle` / `inlineRestartFromBeginning` (verified: 0 references), so the global key handler's pause/restart do nothing while the wall detail player is up.

### 🟠 P2 — Feature parity differs per mode (the root "shaky" symptom)
Same video, three behaviors: Overlay resumes + shows subtitles + handles errors; Detail Pane does none of that; Full Screen doesn't fullscreen. Users experience this as unpredictable playback.

### 🟠 P2 — Fragile mode-switch choreography
Relocating a playing video across modes relies on `isPlayingInline=false` → `DispatchQueue.main.async { isPlayingInline=true }`, spanning **two different player owners** with their own `.onChange(of: isPlayingInline)` teardown/startup. Ordering is load-bearing and defended only by comments. This is prime territory for double-players, stale windows, and missed teardown (the dead `VideoDetailView` even has special-case logic for "full → overlay leaves the window open").

### 🟡 P3 — Logic triplication / drift
Resume-banner state machine, subtitle discovery, status monitoring, and position persistence are copy-pasted between `VideoDetailView` and `OverlayInlinePlayerView`, and **absent** from the inspector. Any fix must currently be made in 2–3 places; they have already drifted.

### 🟡 P3 — Mode-agnostic "Play" affordance
The inspector title-row `play.fill` button just sets `isPlayingInline = true` with no mode, so it plays in whatever mode was last selected — non-obvious. Hero tap and filmstrip tap force `.detailPane`; the expand button forces `.overlay`; there is no inspector affordance for Full Screen at all.

### 🟡 P3 — Minor smells
- Two separate `.onChange(of: video?.filePath)` handlers in the inspector (lines 63 and 74) that both run on every selection change.
- `VideoPlayerView.swift` is a third, unrelated bare `VideoPlayer` — check whether it is still used anywhere or is also dead.

---

## Proposed redesign

**Principle: one playback engine, three host containers.** A mode should change *where* the player is mounted, never *what* the player can do.

### 1. Extract a single playback engine
Create one reusable unit — either an `@Observable` `InlinePlaybackController` (owns the `AVPlayer`, exposes intents) or a `PlayerEngineView` — that encapsulates, exactly once:
- `isPlayable` preflight + missing-file detection
- `AVPlayer` creation, `AVPlayerItem.status` monitoring + error surface
- resume-position load **and** save (`PlaybackPositionStore`)
- resume banner + fade state machine
- sidecar subtitle discovery + `SubtitleTrack`
- `recordPlay`
- Space / Shift-Space (`inlinePlayPauseToggle` / `inlineRestartFromBeginning`)

`OverlayInlinePlayerView` is already ~90% of this — it is the natural basis for the shared engine. (Salvage the engine, then delete `VideoDetailView`.)

### 2. Make the three modes thin hosts of the same engine
- **Detail Pane** → engine mounted in the inspector hero frame.
- **Overlay** → engine mounted in the floating `OverlayPlayerPanel`.
- **Full Screen** → engine's player surfaced in the borderless window (keep `FullscreenInlinePlayerWindowController`, but driven by the shared engine/controller so resume, subtitles, errors, and recordPlay all work there too).

A controller-based design is cleaner for Full Screen, because an `AVPlayer` can move between an in-pane `FloatingPlayerView` and the window's `AVPlayerView` **without** a stop→restart (no re-buffering, no lost position), eliminating the fragile `DispatchQueue.main.async` relocation.

### 3. Collapse the state model to one source of truth
Replace the three booleans with a single value, e.g.:
```swift
enum InlinePlayback: Equatable {
    case idle
    case playing(videoID: String, mode: InlinePlaybackMode, startAt: Double?)
}
```
Mode switches mutate `mode` atomically; hosts react to one published value. `inlinePlaybackReshapesBrowser`, `inlineOverlayActive`, etc. become trivial computed reads. This removes the ordering hazards.

### 4. Delete the dead path
Once the engine is extracted, remove `libraryContent`, `contentBody`, `libraryNavBar`, `detailContent`, and `VideoDetailView` (and `VideoPlayerView` if unused). Re-home the playback-mode segmented control into the live `curatedHeaderBar` (or inspector) so mode is discoverable without the menu.

---

## Suggested sequencing (low-risk → structural)

**Phase A — stop the bleeding (small, shippable):**
1. Route Full Screen in the wall to `FullscreenInlinePlayerWindowController` (fixes P1 fullscreen).
2. Give the inspector hero player resume save/load, `recordPlay`, and the Space/Shift-Space observers (fixes the worst Detail-Pane regressions) — even before the big refactor.

**Phase B — unify:**
3. Extract the shared engine from `OverlayInlinePlayerView`; mount it in all three hosts.
4. Introduce the `InlinePlayback` enum; delete the booleans and the deferred-relocate hack.
5. Move the `AVPlayer` between hosts instead of stop→restart.

**Phase C — cleanup:**
6. Delete dead `VideoDetailView` + legacy layout; surface the mode control in the live chrome.

Phase A alone will make playback feel dramatically less shaky; B/C make it correct and maintainable.

---

## Verification notes (how these findings were confirmed)

- `libraryContent` references: **0** (dead). `VideoDetailView` reachable only via dead `detailContent`.
- `FullscreenInlinePlayerWindowController` constructed only at `VideoDetailView.swift:464` (dead).
- `CuratedWallInspector` references to `PlaybackPositionStore`, `SubtitleTrack`, `playerError`, `isPlayable`, `recordPlay`, `inlinePlayPauseToggle`, `inlineRestartFromBeginning`: **0**.
- Detail-pane play paths in the wall: hero tap (`heroView` onTap), filmstrip tap (`filmstripSeekAndPlay`), title `play.fill` (mode-agnostic) → all land in `startLocalHeroPlayer()`.

---

## Requirements (locked, 2026-06-30)

These are the behaviors playback must guarantee **in every mode**:

1. **Filmstrip click → seek-and-play at the clicked time, regardless of mode.** (Today it wrongly forces Detail Pane — must instead start in the configured mode and pass the seek time.)
2. **Playback starts in the mode indicated by the setting** (detail pane / overlay / full screen). Play affordances must not override the configured mode.
3. **Subtitles (sidecar `.srt`) display if available, regardless of mode.**
4. **On stop — for any reason — the current position is saved and resumed next time** (unless explicitly overridden, e.g. "Start at beginning").

All four reduce to one thing: **feature parity across modes**, which the single-engine redesign provides directly.

## Decisions (2026-06-30)

1. **Full Screen = borderless** (edge-to-edge), as in the current `presentEdgeToEdge` path.
2. **Browser reshape — recommendation: drop it.** In the Wall + Inspector layout the player lives inside the fixed inspector hero, so the old "freeze + resize the browser column + re-anchor scroll + restore list columns" machinery (`inlinePlaybackReshapesBrowser`, `playbackLayout`, `reapplyListColumnCustomizationAfterPlaybackExit`, the scroll re-anchor in `isPlayingInline.didSet`) no longer serves a purpose. Removing it deletes a large class of the "shaky" layout pulses. *Proceeding on this recommendation unless told otherwise.*
3. **Visible playback-mode control — yes.** Surface the mode segmented control in the live Wall chrome (header bar / inspector), not only ⌥⌘1/2/3.
4. **Engine shape — recommendation: `@Observable` controller** (`InlinePlaybackController`) that owns the `AVPlayer` + `SubtitleTrack` + resume/error state. A controller lets the *same* `AVPlayer` move between hosts (inspector hero ↔ overlay panel ↔ borderless window) **without stop→restart**, so switching modes mid-playback keeps position and avoids re-buffering. Host views become thin and stateless. *Proceeding on this recommendation unless told otherwise.*
