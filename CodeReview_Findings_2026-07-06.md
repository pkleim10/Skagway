# Code Review Findings — 2026-07-06

Scope: full `feature/curated-wall` branch diffed against `main` (the entire Curated Wall redesign, pre-v1.0). Basic `/code-review` (high-effort, single-session, 8 finder angles + 1-vote recall-biased verification). 10 findings survived verification, all CONFIRMED, ranked most-severe first. Two additional candidates were checked and refuted (filter-drawer resize was relocated not removed; one duplication sub-claim didn't hold).

Status legend: ☐ open · ✅ fixed · ⏭️ deferred (with reason)

---

## Correctness / data-integrity (fix before v1.0)

### 1. ✅ Migration hardcodes matchMode, silently breaks existing "match ANY" collections (fixed build 666)
- **File:** `VideoMaster/Database/DatabaseMigration.swift:164`
- The migration that backfills existing Collections into the new rule-group structure hardcodes the new group's `matchMode` to `'all'` instead of copying the collection's existing `matchMode`.
- **Failure scenario:** `GroupedMatcher` combines rules *within* a group via the group's own mode, and combines *groups* via the outer collection mode. For a single-group backfill, the outer mode is a no-op (`allSatisfy`/`contains` over one element are equivalent), so the hardcoded group mode is what actually governs matching. Any user with a pre-existing "match ANY" collection will have it silently start requiring ALL rules to match after this migration runs on their real database — often collapsing to zero results, with no data loss but wrong semantics.

### 2. ✅ Wall grid's Remove/Delete ignore multi-selection (fixed build 667)
- **File:** `VideoMaster/Views/Inspector/CuratedWallGrid.swift:180`
- "Remove from Library" and "Delete Video…" in the Wall grid's context menu act only on the right-clicked video, unlike every other action in the same menu.
- **Failure scenario:** Select 8 videos, right-click one. Re-encode, Move Files, Regenerate Thumbnail, and Not a Duplicate all correctly act on the whole selection (`ids = selectedVideoIds.contains(video.id) ? selectedVideoIds : [video.id]`), but Remove from Library / Delete Video hardcode `[video.id]`. The confirmation dialog implies the whole selection is affected; only 1 of 8 is actually removed/deleted. `LibraryListView`'s equivalent menu handles this correctly — confirms this is a Wall-specific regression.

### 3. ✅ Mixed-value custom-metadata field silently wiped to blank on blur (fixed build 668)
- **File:** `VideoMaster/Views/Inspector/CuratedWallInspector.swift:102`
- Clicking into a mixed-value custom field and clicking away — no typing required — overwrites every selected video's differing value with blank.
- **Failure scenario:** `flushPendingCustomEdits()` correctly skips persisting over mixed fields, but the separate `.onChange(of: focusedCustomFieldId)` blur handler has no such guard and no changed-value check — it unconditionally persists the blank "Multiple values" placeholder.

### 4. ☐ Rename has no guard against racing an in-flight file move
- **File:** `VideoMaster/Views/Inspector/CuratedWallGrid.swift:95`
- Every other file-touching action in the context menu (Open With, Re-encode, Move Files, Regenerate Thumbnail, Remove/Delete) is `.disabled(isMoving)`; Rename is not, nor is the global Enter-key rename shortcut, nor `renameVideo()` itself.
- **Failure scenario:** A user can rename a file while a background `MoveJob` is mid-copy from the same path; `renameVideo()` calls `FileManager.moveItem` on that same URL concurrently with the in-flight copy, risking a corrupted or orphaned file.

---

## Performance regression

### 5. ☐ Recurrence of the eager-`.contextMenu` bug in "Open With"
- **File:** `VideoMaster/Views/Inspector/CuratedWallGrid.swift:109`
- `NSWorkspace.shared.urlsForApplications(toOpen:)` (a real Launch Services query) runs directly inside the `Menu("Open With")` builder, not inside a `Button` action.
- **Failure scenario:** This is the same file that already documents (in a comment) that `.contextMenu` builders are evaluated eagerly per instantiated card on every grid render, and that a prior fix moved a different computation (selection URLs) into a `Button` action after it caused a 75-second hang at 12k videos. Line 109 is a distinct, unfixed instance of the exact same bug class.

---

## Feature/UX regressions vs. the old detail view

### 6. ☐ Multi-select "File Size" always shows "—"
- **File:** `VideoMaster/Views/Inspector/CuratedWallInspector.swift:407`
- Shows "—" for any multi-selection even when every selected video is byte-identical, instead of the shared value (as duration/codec/dateAdded correctly do via the same `commonValue`-style pattern).

### 7. ☐ "Created" and "Last Played" rows dropped from the Inspector
- **File:** `VideoMaster/Views/Inspector/CuratedWallInspector.swift:363`
- The old detail view showed file creation date and last-played timestamp; neither appears anywhere in the new Inspector.

### 8. ☐ Duration filter has no min/max cross-validation
- **File:** `VideoMaster/Views/Components/CuratedWallFiltersDrawer.swift:449`
- Min/Max are independent text fields with no clamping or swap logic; an inverted range (e.g. Min=100, Max=5 minutes) silently produces zero results with no hint that the range itself is the problem.

### 9. ☐ Manual subtitle loading/toggle removed
- **File:** `VideoMaster/Views/Detail/InlinePlaybackController.swift:238`
- The old view had a Toggle for subtitles on/off plus a "Load Subtitles…" button (`NSOpenPanel` file picker). The new architecture only auto-discovers a same-named sidecar `.srt`, with no way to disable it or pick a different file.

---

## Maintainability

### 10. ☐ Context menu duplicated near-verbatim between List and Wall grid
- **File:** `VideoMaster/Views/Inspector/CuratedWallGrid.swift:90` (vs. `VideoMaster/Views/Library/LibraryListView.swift:182`)
- ~110 lines of identical button/action/guard logic exist in both files, differing only in how the acted-on id set is derived. This duplication is exactly how finding #2 happened — a fix applied to one copy and not the other.

---

## Refuted during verification (no action needed)
- **Filter-drawer no longer resizable** — refuted. The resize handle was relocated to `ContentView.swift` (`filtersDrawerResizeHandle`), still draggable and persisted via `UserDefaults`.
- **`findTableView` duplication (List vs. `ScrollCommandHandler`)** — inconclusive, dropped rather than reported as confirmed.
