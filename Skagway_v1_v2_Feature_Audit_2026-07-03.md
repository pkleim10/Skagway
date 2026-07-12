# Skagway v1 → v2 Feature Audit

**Date:** 2026-07-03
**Compared:** `main` (v1, pre-redesign) vs `feature/curated-wall` (v2, current branch)
**Relationship:** `main` is the exact merge-base — 0 commits diverged since the branch point. `feature/curated-wall` is 36 commits / 65 files ahead, including two large deletions replaced by new components:
- `Skagway/Views/Detail/VideoDetailView.swift` (1597 lines) → `Views/Inspector/CuratedWallInspector.swift` + `CuratedWallCard.swift` + `CuratedWallGrid.swift`
- `Skagway/Views/Sidebar/BottomFilterColumnsView.swift` (572 lines) → `Views/Components/CuratedWallFiltersDrawer.swift` + `ActiveFilterPills.swift`

Method: `git diff`/`git show` across both branches for every changed file, cross-checked against the branch's own self-audit docs (`CuratedWall_Cleanup_Plan.md`, `Playback_Audit_2026-06-29.md`, `Playback_Redesign_Plan_2026-06-30.md`) and `CHANGELOG.md`. Every claim below is sourced from actual diffs/greps, not inference; the two most surprising findings (drag-and-drop import, collections cap) were independently re-verified against source in this session.

---

## 1. Summary

Most of the risk from this redesign was in the playback engine — the branch forked playback into three inconsistent engines mid-way through, but this was caught by the branch's own `Playback_Audit_2026-06-29.md` and resolved across releases 0.16.0–0.22.0 (now one shared `InlinePlaybackController`). That work is done; this audit does not re-litigate it.

What's left, after checking filters/sidebar, the Inspector/detail view, and top-level app/menu/ViewModel wiring: **1 clear P1, 3 P2s, 6 P3s** of genuinely open, unfixed regressions — plus a longer list of intentional redesigns and net-new features that are not regressions at all.

| Severity | Count | Headline |
|---|---|---|
| P1 | 1 | Drag-and-drop file import no longer works |
| P2 | 3 | Collections list capped at 6; no standalone tag creation; missing-file scan-in-progress indicator dropped |
| P3 | 6 | Filter panel no longer resizable; two metadata fields dropped from Inspector; subtitle info row dropped; corrupt-file metadata auto-refresh orphaned; no manual "rescan missing files"; Surprise Me doesn't scroll pick into view (already tracked internally) |

---

## 2. Confirmed open regressions

### P1 — Drag-and-drop file import is gone
- **v1:** `ContentView.swift:286` — `.onDrop(of: [.fileURL], isTargeted: nil) { ... Task { await vm.importDroppedFiles(urls) } }`
- **v2:** Zero `onDrop` calls anywhere in the tree (verified via `git grep -n onDrop` across all of `Skagway/`). `importDroppedFiles` still exists at `LibraryViewModel.swift:1690` but has zero callers.
- **Impact:** Dragging video files onto the window silently does nothing in v2 — no error, no feedback, the feature just isn't wired up.

### P2 — Collections list capped at 6, no overflow
- **v1:** `BottomFilterColumnsView.swift:246-291` — scrollable list, showed all collections.
- **v2:** `CuratedWallFiltersDrawer.swift:253-254` — `let maxShow = 6`, `Array(viewModel.collections.prefix(maxShow))`, no "show more" affordance.
- **Impact:** Collections beyond the first 6 are unreachable from the filter UI.

### P2 — No standalone "New Tag" creation
- **v1:** `BottomFilterColumnsView.swift:9,67-104` — a `showNewTag` sheet reachable with no video selected, via `createTag()`.
- **v2:** The only tag-creation path is `CuratedWallInspector.swift:687 createAndApplyNewTag()`, which requires a selected video and immediately assigns the new tag to it.
- **Impact:** No way to pre-create an unused/library tag before you have a video selected.

### P2 — Missing-file "unscanned" indicator dropped
- **v1:** `BottomFilterColumnsView.swift:140,557-571` — `sidebarRow(unscanned:)` showed `—` instead of a stale count while the missing-file scan was in progress.
- **v2:** `libraryRow` in `CuratedWallFiltersDrawer.swift:236` has no `unscanned` parameter — always shows `viewModel.libraryCounts.missing`, even if stale.
- **Impact:** Minor but real — user can't tell a shown "missing" count is stale vs current.

### P3 — Manual drag-to-resize of the filter panel is gone
- **v1:** `ResizableVerticalSplitView`, user-draggable height, persisted per view mode.
- **v2:** Fixed 320pt animated well (`ContentView.swift:296-311,322-345`) — open/close only via `isCuratedWallFiltersDrawerOpen` (⌘⇧F), no resize.

### P3 — Two Inspector metadata fields dropped
- **v1:** "Created" date and "Last Played" timestamp, `VideoDetailView.swift:858-872`.
- **v2:** No equivalent row in `CuratedWallInspector.swift`'s facts row (`commonResFps`/`factsRow`, lines ~363-368). Play count is still shown. Multi-select file size also regressed to always "—" instead of showing a common value when all selected files share one.

### P3 — Subtitles metadata/info row not surfaced in the Inspector
- **v1:** `VideoDetailView.swift:875-899` — a dedicated subtitles row (filename shown when loaded, "Load…" affordance).
- **v2:** No equivalent row found in `CuratedWallInspector.swift`. Note: subtitle *playback* itself still works fine via the shared `InlinePlaybackController` — this is specifically the informational/manual-load UI, not playback.

### P3 — `refreshMetadataIfCorrupt` orphaned
- **v1:** Called from `VideoDetailView.swift:1243` — re-checks metadata when a corrupt file is reselected (in case it was externally repaired).
- **v2:** Function still exists (`LibraryViewModel.swift:1958`) but has zero callers anywhere in `Views/`.

### P3 — No manual "rescan for missing files" trigger
- **v1:** Toolbar button at `ContentView.swift:377`, shown when sidebar filter = Missing.
- **v2:** Auto-scan-on-launch still runs (`LibraryViewModel.swift:110`), but no user-facing manual re-trigger exists anywhere in `Views/`.

### P3 — Surprise Me doesn't scroll the pick into view in the Wall grid *(already tracked internally, not a new finding)*
- `finishSurpriseScrollIfNeeded` is orphaned in v2. This is the same gap the branch's own `CuratedWall_Cleanup_Plan.md` already flagged: `CuratedWallGrid` has no scroll-to-selection infrastructure (only the list view does).

---

## 3. Regressions already found and fixed on this branch

These were real gaps introduced mid-redesign, but the branch caught and closed them before this audit — listed here so they aren't rediscovered as "new" problems.

| Item | Source |
|---|---|
| Grid had no visible scrollbar | `CuratedWall_Cleanup_Plan.md` item 1, fixed `02015b0` |
| "Import New" toolbar affordance missing | `CuratedWall_Cleanup_Plan.md` item 2, fixed `3f0af5c` |
| "Surprise Me" toolbar affordance missing | `CuratedWall_Cleanup_Plan.md` item 3, fixed `3f0af5c` |
| No way to delete/rename a tag | `CuratedWall_Cleanup_Plan.md` item 8, fixed — now in Inspector via right-click |
| "Last used size" didn't remember full-screen | `CuratedWall_Cleanup_Plan.md` item 7, fixed `8403837` |
| Playback forked into 3 inconsistent engines (resume, subtitles, errors, recordPlay, Full Screen literally broken) | `Playback_Audit_2026-06-29.md` (full P1/P2 writeup), resolved by the single shared `InlinePlaybackController` + `FloatingPlayerPanel` redesign, CHANGELOG 0.16.0–0.18.0 |

---

## 4. Intentional redesigns (not regressions)

| v1 behavior | v2 behavior | Note |
|---|---|---|
| 3 playback modes (detail pane / overlay / full screen) | Single resizable player, continuous size + true full-screen | `Playback_Redesign_Plan_2026-06-30.md`, CHANGELOG 0.16.0–0.18.0 |
| Always-visible bottom filter strip | Collapsible top filters drawer (⌘⇧F) | `CuratedWall_Readiness_Checklist.md` decisions §C/§F |
| Rating filter: multi-select via ⌘-click | Single-star tap-to-toggle | Simplified interaction |
| Tag filter: click = single-select, ⌘-click = additive | Every tap toggles add/remove (uniform) | Simplified; tag search box added |
| Keyboard shortcuts: ⇧⌘R (Remove), ⌥⌘R (Restart), ⌥⌘1/2/3 (playback mode) | ⌥⌘R (Remove), ⌥-Space / ⌥⌘B (Restart), ⌥⌘F (Show in Finder), ⌘⇧F (filters), ⌃⌘F (full screen) | Deliberate rationalization, CHANGELOG 0.20.0 |
| Title/rename UI lived in the detail pane | Moved to grid-card right-click context menu | `CuratedWallGrid.swift`/`CuratedWallCard.swift` |
| "Play Video" (external) button in detail pane | Moved to grid context menu, "Play in External Player"; Inspector's Play button now plays inline | — |

---

## 5. Net-new in v2 (not a v1 feature — included for completeness)

Duration filter with presets · tag search box in the filters drawer · tag-hover popover for truncated names · "Modify Filmstrip…" in Wall grid context menu · "Regenerate Thumbnail" · "Make Thumbnail from Current Frame" · re-encode queue manager with abort/retry/restore/move-to-top · arrow-key grid navigation · Home/End go-to-first/last · custom-metadata-aware sort + List view columns · Tag blind default-state setting · tag delete/rename (didn't exist at all in v1's detail view).

---

## 6. Open questions worth a deliberate decision

1. **Drag-and-drop import (P1)** — restore `.onDrop` wired to the existing `importDroppedFiles`, or is drag-and-drop intentionally deprecated in favor of the "Add Folder"/"Import New" buttons?
2. **Collections cap of 6 (P2)** — raise/remove the cap, or add a "show all" affordance, matching v1's unlimited scrollable list?
3. **Standalone tag creation (P2)** — worth restoring a filters-drawer path to create a tag with no video selected, or is "create while assigning" acceptable going forward?
