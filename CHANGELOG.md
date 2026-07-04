# Changelog

**VideoMaster changelogs are maintained live by agents.**

## How maintenance works (for agents)

**Two phases:**

1. **Live updates (development / every commit)**
   - After changes + `bash scripts/build_and_install.sh`, append high-level summaries to the `## Unreleased` section.
   - Do this before or as part of the commit.

2. **Consolidation (on release)**
   - After running the build script for a release, convert the `## Unreleased` content into a new release header:
     ```
     ## X.Y.Z (build NNN) - YYYY-MM-DD
     ```
   - Clear the Unreleased section.
   - The release commit message should align with the consolidated text.

Most recent releases sit directly after the Unreleased section.

See `AGENTS.md` and `.cursor/rules/build-deploy.mdc` for the full agent and release workflow.

### Agent quick checklist
- After `bash scripts/build_and_install.sh` → append high-level bullets to `## Unreleased`.
- Before committing → ensure the Unreleased section accurately reflects the changes in this commit.
- On release (after the final build) → promote Unreleased content into a versioned header and clear it.

---

## Unreleased

- **Removed the 6-collection cap in the filters drawer's Collections card.** Beyond 6, collections were simply unreachable — no scroll, no indication more existed. Since collections are listed alphabetically (not ranked), there's no meaningful "top N" to prefer, so the card now always shows every collection, scrolling internally past its usual height (~168pt) instead of growing unbounded — no expand/collapse step needed.
- **List view context menu reordered to match the Wall grid's.** Was Play → Show in Finder → Open With → Rename → Re-encode → Move Files (no divider between Open With and Re-encode); now Play → Show in Finder → Rename → Open With → *divider* → Re-encode → Move Files, same as the grid. The rest (Modify Filmstrip / Regenerate Thumbnail, Remove from Library / Delete Video…, and their dividers) already matched.

## 0.23.0 (build 605) - 2026-07-03

- **New: Move queue + safety for cross-volume "Move Files…".** Same-volume moves are still an instant atomic rename, unchanged. A move onto a different volume is a real copy + delete and previously gave zero feedback (the `isMoving`/`moveProgress` state existed but nothing rendered it) — worse, it operated on the real source file with no crash safety. Now: the copy lands at a `<name>.moving` temp at the destination first, is size-verified, promoted to the final name, and only then is the source deleted — a crash mid-copy leaves at worst an orphaned temp file, swept automatically on next launch; the original is never at risk. Progress surfaces in a new header status pill (next to the re-encode pill) that opens a Move Queue manager (abort / move-to-top / retry / dismiss, one move at a time). While a move is active, that video's Delete / Move / Re-encode / Remove-from-Library / Open With are disabled in both the Wall grid and List context menus, and the Wall card shows a dimmed spinner badge over the thumbnail so it's visibly "frozen" without needing to right-click.
- **Move Queue manager polish:** newly queued moves now appear at the top of the list (not the bottom); the currently-moving file pops to the very top the moment it starts, ahead of everything still queued behind it; a **Clear** button in the header (shown only when there's something to clear) removes all completed rows at once, same as a browser download manager's "clear completed."
- **Fix: moving multiple selected videos could silently drop one from the selection.** `selectedVideoIds` is pruned to valid ids whenever `videos` changes — including via GRDB's *independent* observation stream, which reacts to a rename on its own async path and can race the move code's own selection update arbitrarily. A first attempt (capture-then-apply) narrowed the window but didn't close it, since the stream could still land its prune before or after in a way that left the new path never inserted. Actually fixed by updating `videos` locally and synchronously ourselves right after the DB write (mirroring the existing pattern in `videoConvertedToMP4`) — the rename-then-reselect now happens in one uninterrupted block with no `await` in between, so nothing can interleave a stale prune; GRDB's later redundant delivery of the same data becomes a no-op. Applies to both the same-volume and cross-volume move paths. Pre-existing in `main`'s move code too, not introduced by the new queue.
- **Restored drag-and-drop file import.** Dropped during the Curated Wall redesign along with the old nav bar; dropping video files (or folders) onto the main window now imports them again, same as `main`. Drop target covers the whole Wall + Inspector split (broader than the old grid-only target), so a drop landing on the Inspector panel still imports.
- **Fix: "Delete Video…" from the Wall grid's context menu did nothing.** The confirmation dialog was only mounted in the (dead) legacy `LibraryGridView` and in `LibraryListView` — triggering delete from the Wall grid set the confirmation flag with nothing listening, so it silently no-oped until you switched to List view. Added the same `.confirmationDialog` to `CuratedWallGrid`. Also renamed the Wall grid's menu item from "Delete" to "Delete Video…" to match List view.

## 0.22.0 (build 597) - 2026-07-02

- **Reworked "Re-encode to MP4" for safety and control.** The original file now stays fully intact under its real name until the encode provably succeeds: ffmpeg writes a temporary `<name>_convert.mp4`, and only on success is the original renamed to `<name>_backup.<ext>` and the temp promoted to the final `<name>.mp4`. A crash or abort mid-encode can no longer cost you the source. Backups are now **kept** (not silently trashed) so you can restore or delete them later.
- **New: Re-encode Queue manager.** A status pill in the header (live spinner + percentage while encoding) opens a queue dialog listing every job. Per-item actions: **Abort** (queued or in-progress — terminates ffmpeg and discards the partial), **Move to Top** (reorder pending jobs), **Restore** (undo a conversion: trash the `.mp4`, rename the backup back to the original), **Delete Backup** / **Delete All Backups**, **Retry** (for failed jobs), and **Dismiss**. Conversions run one at a time.
- **New: queue survives relaunch.** Pending jobs are persisted and resume automatically on next launch; a job interrupted mid-encode is re-queued and its stray temp file swept. Completed entries age out of the list after 30 days (backup files are left untouched).
- Previously the re-encode status was computed but shown nowhere — it now surfaces in the header pill.

## 0.21.0 (build 594) - 2026-07-02

- **New: "Play from Beginning" (⌥-Space)**: starts the selected video from 0, ignoring any saved resume position. When a video is already playing, ⌥-Space restarts it from the beginning — this replaces the old ⌥⌘B "Restart from Beginning" shortcut (the menu item remains, without a shortcut). Plain Space is unchanged (resume / play-pause).
- **Fix: unreachable-file playback no longer flashes and vanishes**: if the video's drive isn't mounted (or the file otherwise can't be opened), the player panel now stays open and shows the existing "Playback Failed" error card (Open in External Player / Dismiss) instead of instantly tearing down the panel before the message can render.
- **New: "Regenerate Thumbnail"** context-menu action (grid + list, single or multi-selection): picks a fresh random position between 10%–90% of the video's duration and regenerates both the thumbnail and the detail-preview still, for videos whose auto-picked frame (10% in, capped at 30s) looks bad — a black frame, title card, or blurry transition. Also fixes a latent race where a slow detail-preview fetch for a previous card state could land late and overwrite a newer one.
- **New: "Make Thumbnail from Current Frame"** — a camera icon in the floating player panel (and a matching menu item) captures the exact frame on screen right now and sets it as the thumbnail + detail preview, replacing whatever was cached. The precise-control counterpart to "Regenerate Thumbnail": scrub to the exact moment you want, then capture it. Uses a zero seek tolerance so it lands on the exact frame rather than a nearby keyframe. No mouse affordance in true full-screen yet (menu item still reaches it via the app-wide command). Shortcut: ⌥⌘M.
- **New: "Modify Filmstrip…"** added to the Wall grid's context menu (already present in List); the Inspector now actually refreshes after using it — it was already being signaled but nothing was listening.
- **Fix: compact player no longer snaps back when dragged.** Moving the title bar exited compact mode without clearing the compact flag, so the panel's position kept resetting to the fixed top-right slot the moment the drag ended. It now exits compact on the first drag frame (freezing the current size first, so there's no resize jump) and stays wherever it's dropped.
- **New: Tag blind default-state setting** (Settings → Tags): the Inspector's "Add tags" blind can be set to always closed (previous behavior), always open, or left as-is (last used) on each new selection.
- **Assigned tags pop more** in the Inspector: stronger accent fill, full-opacity border, semibold text — same accent color, no new palette.
- **New: "Go to First" / "Go to Last"** (Home / End keys, list and grid): selects and scrolls to the first/last video in the current filtered order. List scrolling uses the same header-aware positioning as other jump commands so the first row lands fully clear of the column header instead of partially hidden under it.

## 0.20.0 (build 578) - 2026-07-02

- **⌘F now focuses the search field**, matching the system-wide Find convention. Existing search text is auto-selected via AppKit's standard first-responder behavior.
- **Fullscreen toggle moved to ⌃⌘F** (Control-Command-F, the macOS-standard fullscreen shortcut), freeing up plain ⌘F for search focus.
- **Keyboard shortcut modifiers rationalized app-wide**: every shortcut now follows one consistent rule — ⌃ is reserved solely for the OS-mandated fullscreen binding, ⌥ marks an alternate/secondary action (Clear Filters, Toggle Thumbnail/Filmstrip, Show in Finder, Restart from Beginning, Remove from Library), and ⇧ marks an action that reveals or adds UI (Surprise Me, Toggle Filters, Add Folder). Restart from Beginning moved ⌥⌘R → ⌥⌘B; Remove from Library moved ⇧⌘R → ⌥⌘R to resolve the one letter collision this created.

## 0.19.0 (build 557) - 2026-07-02

- **Arrow key navigation in grid view**: ← / → move to the previous / next video; ↑ / ↓ jump one row up or down (same column position). Navigating scrolls the selection into view. Keys are ignored when a text field (search, inspector custom fields) is focused.
- **Fix: inspector custom-field edit lost on selection change**: editing a text/number custom field and then clicking another video no longer drops the edit. Values are now flushed to the correct video before the inspector reloads for the new selection.
- **Fix: spacebar focus hijack and fullscreen-to-windowed state bug**: spacebar no longer types into the search field on launch; fullscreen-to-windowed transition now correctly restores player state.

## 0.18.0 (build 551) - 2026-07-01

- **Filmstrip click now seeks to the clicked frame**: clicking a frame in the inspector filmstrip starts playback at that frame's exact timestamp. The mapping is row-aware (rows × columns grid) rather than treating the x position as a 0–100 % scrubber. `ThumbnailService` exposes `filmstripGrid(in:)` to recover the grid from the composite's point size, so per-video grid choices are honoured without persisting them separately.
- **Removed S / M / L player size presets**: the floating player is now resizable by drag, making the three fixed-fraction preset buttons redundant. The bottom-right controls are simplified to just **Compact** (inspector footprint, top-right) and **Full screen**.

## 0.17.0 (build 548) - 2026-07-01

- **Custom metadata fields in sort and List View columns**: all non-text custom field types (String, Number, Date, Date & Time) now appear in the toolbar Sort menu (after a separator below the built-in options) and as right-click-toggleable columns in List View. Sort uses pre-built typed value maps for concrete comparisons — no per-row string parsing, zero performance regression. Missing values sort last. Selection, direction, and persistence match built-in sort behavior.
- **Floating player is now movable**: drag the title bar to reposition the panel anywhere in the content area. Compact always snaps to the top-right inspector footprint (unchanged). S/M/L presets center the panel on the application window when clicked. The resize handle (bottom-left) still keeps the top-right corner pinned while resizing. Position persists across launches; clamping handles window-size changes.
- **Sort fixes**: clicking a List View column header now re-sorts immediately (was moving the caret but not applying); selecting a custom-field sort from the toolbar dropdown now moves the column header caret to that column. Arrow direction follows the universal convention (↑ = ascending).

## 0.16.0 (build 520) - 2026-07-01

- Curated Wall cleanup:
  - Grid now shows the native scroll indicator for all macOS "Show scroll bars" settings, including the legacy space-reserving scroller ("Always" / mouse attached). Fixed by dropping the `GeometryReader` around the grid (which suppressed the legacy scroller) in favor of flexible columns — same 5-column layout, visually identical.
  - Restored **Import New** and **Surprise Me** as left-cluster icon buttons in the header (they were dropped with the old nav bar). Import New shows live scan progress in the header status ("Importing 12/340"). Surprise Me's auto-play was re-wired (its `pendingAutoPlay` consumer had been deleted with the legacy detail view).
  - "Player opens at → Last used size" now remembers **full-screen** (persisted `playerLastWasFullScreen`): entering full-screen sets it; only an explicit windowed choice (compact / S-M-L / drag) clears it, so stopping from full-screen still reopens full-screen.
  - **Inspector tag management redesigned** into two lists: assigned tags (top, tap to unassign) and — behind a collapsible "Add tags" blind — the unassigned tags (tap to assign; right-click to Rename… or Delete Tag with confirmation). New Tag lives in the blind and auto-assigns. Deleting removes the tag from the library and every video. Assigned tags run in a packed flow; the blind is transient (collapses per selection). Closes the "no way to delete a tag" gap.
  - **Inspector detail polish** toward the mockups: title + clickable file-path line (folder icon → reveal in Finder, replacing the separate Finder button); Play/Finder... labels on action buttons; a compact **facts table** (resolution+fps · duration · size / codec · date · plays / subtitles) rendered as a bordered grid with cell separators; removed the redundant path footer below Notes.
  - **Exact colors**: inspector background `#0A1523`, facts table cell `#101E2D` with `#19242F` border/separators; Wall grid background `#030D17`, selected card background `#0C141E`.

- Playback redesign (in progress): unifying the three playback modes into one resizable player surface backed by a single shared `InlinePlaybackController` (resume load/save, sidecar subtitles, error handling, recordPlay, play-pause/restart).
  - Introduced the shared engine and a single `FloatingPlayerPanel` host: one player anchored top-right, shown whenever playback is active, with subtitles, resume banner, and error handling in one place.
  - The panel is **resizable** via a lower-left handle (top-right anchored, jitter-free), clamped between a compact minimum and the available area, with **▭ S M L ⤢** controls: compact (snap to the inspector still/filmstrip footprint), small/medium/large presets, and full-screen. Size is persisted.
  - **True full-screen carry-across**: going full-screen moves the *same* player into a borderless edge-to-edge window (no restart; position + subtitles preserved). Esc stops playback and closes; the bottom-right button exits back to the windowed player still playing.
  - The inspector hero is now still/filmstrip only; the player floats above it. Filmstrip click and hero tap start playback carrying the clicked seek time. Removed the obsolete inspector "overlay" action button.
  - **Settings → Playback**: "Player opens at" preference — Compact / Full screen / Last used size.
  - **Compact is a sticky mode**: while active, the player's size *is* the live inspector still/filmstrip footprint, so it follows the wall/inspector splitter in lockstep (and stays current whether or not the player is visible). Picking S/M/L or drag-resizing exits compact mode; the mode persists across launches.
  - Restart-from-beginning is the ⌘⌥R menu command (Shift+Space proved unreliable on Space in this path).
  - Removed the obsolete three-mode machinery and dead code: `InlinePlaybackMode` + `setInlinePlaybackMode`, the `playInlineStartsFullscreen`/`playInlineInOverlay` settings, `overlayPlayerWidth`, the play-pause/restart counters, the ⌥⌘1/2/3 menu commands, the dead `VideoDetailView`/`VideoPlayerView` and the legacy detail-pane layout (~660 lines).
  - Resume banner now sits below the player's header strip (was overlapping the header/filename).
  - Fixed the flaky spacebar play/pause (a first-responder bug, not the environment): the player now takes keyboard focus when it appears (so Space controls playback during a session without first clicking the transport controls), and the search field's launch-time auto-focus is cleared so Space starts playback on a fresh launch instead of typing into the search box.
  - Fixed the "Player opens at → Full screen" preference (it was opening at the last size): it now waits for the asynchronously-created player before presenting the full-screen window instead of bailing when the player was momentarily nil.

- Playback: removed the legacy "browser reshape" behavior (detail-pane playback used to freeze + resize the browsing column, swap to a separate `playbackLayout`, and re-anchor scroll / restore list columns on exit). In the Wall + Inspector layout the player lives inside the fixed inspector hero, so the wall never moves — this scaffolding was dormant and a source of layout pulses. Removed `inlinePlaybackReshapesBrowser`, the separate `playbackLayout` (now a single shared layout), the detail-pane exit re-anchor/column-restore, and the content freeze during playback. The fullscreen-exit grid repaint (occlusion) is preserved.

- Curated Wall filters drawer: arranged the filter cards (Smart Libraries · Collections · Rating + Duration · Tags) so they **reflow responsively and pack column-major**, preserving reading order as the wall narrows — 4-across when wide, collapsing to 3 columns (`[Smart+Collections] [Rating+Duration] [Tags]`), then 2, then a single stacked column. Each column sizes to its widest card and cards fill their column width (no shrinkwrapping), so the drawer stays readable at any pane width instead of squishing. The last column always stretches to fill the remaining width so its cards reach the drawer's right edge.
- Tag chips: hovering a tag chip reveals the complete tag name in a small popover that escapes the card/drawer bounds, so truncated names are readable. The popover only appears when the name is actually truncated (it never just duplicates a name that already fits). Applies to both the filters drawer and the Curated Wall inspector's Tags section.
- Curated Wall: removed the redundant in-wall header strip (its "Search wall" field and video count duplicated the search + count already in the thin capability bar above). The wall surface now begins directly with the gallery grid.

## 0.15.0 (build 410) - 2026-06-28

- UI (floating overlay player): Made the overlay player panel much more "intentional" as a first-class cinematic object.
  - Replaced raw `windowBackgroundColor` + anonymous splitter with a themed `Color.appSurface` container using `UnevenRoundedRectangle` (xl radius on the leading edge only).
  - Added a subtle `appAccent` outer stroke so the panel reads as a deliberately placed surface rather than leftover window space.
  - Redesigned the width splitter as a visible blue-tinted grip (three stacked capsules) that clearly communicates "this panel is adjustable".
  - Framed the `FloatingPlayerView` with `.appMediaFrame()` + breathing room so the video feels contained instead of bleeding to the edges.
  - Added a compact header bar (filename + close button) using design tokens; this makes the floating player read as a summoned panel, not just "video in a box".
  - The treatment deliberately avoids heavy shadows/materials on the resizable container itself (to preserve smooth live dragging) while still delivering strong visual presence through surface, rounding, accent, and framing.
  - Header close button stops inline overlay playback cleanly.
  - Build 409.

- UI (remaining chrome & editors sweep): Completed the visual pass on the last major stock-looking areas.
  - Detail pane Thumbnail/Filmstrip switcher: replaced stock `.segmented` Picker with `AppSegmentedControl` for full consistency.
  - Overlay player resume banner and error overlay: updated to use `Material.appFloatingMaterial`, `appSurface`, `appAccent` strokes, `appText*` colors.
  - `FilmstripConfigView`: wrapped in glass card, app colors for labels, accent-tinted Generate button, improved steppers.
  - `TagEditorView` & `TagToggleChip`: switched from `accentColor`/`secondary` to `appAccent`/`appTextSecondary`/`appSurface`.
  - `CollectionEditorView`: updated ALL/ANY pill and labels to use `appAccent`/`appTextSecondary`.
  - Settings tabs (Application, Library, Data Sources, List Columns, Custom Metadata, File Ext, etc.): swept `.secondary`/`.tertiary` → `appTextSecondary`/`appTextTertiary`; added `appAccent` tint to key pickers.
  - Various remaining `.bordered` buttons in detail/overlay now consistently tinted where they weren't.
  - Split view surfaces and surrounding chrome already using design tokens; deep NSSplitView divider drawing left as system thin (common limitation).
  - Build 407.

- UI (status bar): Styled the bottom status bar to match the Cinematic Blue design system.
  - Subtle `Color.appSurface.opacity(0.55)` background with a thin `appDivider` top separator.
  - All labels use `Color.appTextSecondary`.
  - Progress indicators tinted with `Color.appAccent`.
  - Consistent `.caption` typography and tight vertical padding.
  - Replaces the previous stock `.bar` material and raw `.secondary` styles.
  - Build 405.

- UI (LandingView): Full Cinematic Blue redesign of the first-impression screen shown when no library is open.
  - Deep `appBackground` full-window treatment.
  - Large, well-weighted title in `appTextPrimary`; subtitle in `appTextSecondary`.
  - Main actions grouped in a prominent glass/surface card (`Material.appSubtleGlass` + `appSurface`) with subtle `appAccent` border and generous `AppRadius.xl`.
  - Primary "Create in default" uses borderedProminent tinted with `appAccent`.
  - Other create/open actions styled consistently with `appAccent` tint.
  - "Open recent" section has a clean divider and hoverable recent items using `appHover` + rounded surfaces.
  - Tighter, more intentional spacing using `AppSpacing` scale.
  - Overall more premium and opinionated dark-first landing experience.
  - Build 404.

- UI (search): Replaced the stock `.searchable` field with a custom styled search pill inside the library nav bar for full Cinematic Blue treatment.
  - Magnifying glass icon + "Search videos" placeholder.
  - Clear (x) button appears when text is present.
  - Focus ring uses `appAccent` (stronger when focused).
  - Uses `appSurface`, `appTextPrimary/Tertiary`, `AppRadius`, `AppSpacing`.
  - Integrated after the sort control; the bar's glass container frames it nicely.
  - Stock searchable behavior removed (no duplicate field); search logic in LibraryViewModel is unchanged.
  - Build 403.

- UI (empty states & placeholders): Styled the "No Videos" empty state and the "Select a video" detail-pane placeholder with the Cinematic Blue design system.
  - Both now use a subtle glass/surface card treatment (Material + appSurface + thin accent border) for a designed, contained look instead of raw floating text.
  - Consistent semantic colors: `appTextPrimary/Secondary/Tertiary`.
  - Proper `AppSpacing` and `AppRadius`.
  - "Add Folder" button tinted with `appAccent`.
  - "Select a video" now includes a short helpful subtitle and stronger visual weight.
  - Build 402.

- UI (top chrome — Priority 1): Finished styling the library nav bar and main toolbar for visual consistency with the Cinematic Blue design system.
  - Replaced the last remaining stock `.segmented` picker (Playback Mode: Detail/Overlay/Full Screen) with `AppSegmentedControl`.
  - Gave the inline library nav bar (directly above grid/list) a matching glass container (Material + appSurface + subtle accent border), same language as the custom segmented controls and bottom filter strip.
  - Restyled the remaining stock buttons in the library nav bar:
    - Columns button
    - Sort menu trigger
    - Scroll navigation cluster (top / page up / page down / bottom)
  - Introduced reusable `.appNavBarButton()` modifier (plain style + surface fill + rounded clip + thin accent ring) to keep the treatment consistent and easy to maintain.
  - Tinted the main window toolbar action buttons (Add Folder, Import New, Surprise Me) with `Color.appAccent`.
  - Removed `.controlSize(.small)` and raw `.bordered` styles from the chrome.
  - Build 401.

- UI (grid): Made selected video cells pop more distinctly.
  - Stronger outer selection: `appAccent.opacity(0.30)` fill + full `appAccent` 2pt border (was subtle 0.22 wash + 0.85 opacity).
  - Thumbnail now gets its own prominent blue accent ring (2pt `appAccent`) when the cell is selected, in addition to the outer card treatment. This makes the actual video content stand out.
  - Filename becomes semibold when its cell is selected.
  - All changes are still lightweight (simple fills/strokes, no per-cell heavy effects).
  - Build 399.

- UI (top nav bar): Replaced the stock segmented pickers with a custom `AppSegmentedControl` for View Mode (List/Grid) and Grid Size (S/M/L).
  - Proper sliding pill selection indicator using `.matchedGeometryEffect` + spring animation.
  - Outer container uses `Material.appSubtleGlass` + `appSurface` with a thin `appAccent` border.
  - Selected segment: `appAccent` tinted fill + stroke; bold semibold primary text.
  - Unselected: secondary text color.
  - Fully integrated with existing side-effects (preferences save + scroll-to-selected on view switch).
  - Removes one of the strongest remaining "generic macOS" visual elements in the main browsing UI.
  - Build 396.

- Bugfix (top nav bar): The custom `AppSegmentedControl` for List/Grid and S/M/L was expanding to a huge height (~4 inches) because it had no explicit height and the selection pill used an unconstrained `RoundedRectangle` inside a `ZStack`. When the vertical split's top pane proposed a large height (from saved layout or measurement), the shapes filled it.
  - Fix: Added `.frame(height: 28)` to keep the control compact like stock segmented controls.
  - Refactored selection indicator to use `.background` on the segment content (the background sizes exactly to the label + padding, no more ZStack + free shape).
  - Reduced internal vertical padding slightly for fit.
  - Build 397.

- Polish: Made the "little bounce" you like when the grid reorders or changes density (via grid size or window width) explicit.
  - Added `.animation(.spring(response: 0.38, dampingFraction: 0.80), value: viewModel.gridSize)` to the `LazyVGrid`.
  - This captures the pleasant springy repositioning of cells (previously purely implicit) so it stays consistent as we continue the visual work.
  - The effect happens on S/M/L changes (now driven by the custom segmented control) and when the number of columns recalculates.
  - Reorders from sorting also continue to get lively movement because we only force-recreate the grid on structural set changes, not pure order changes.
  - Build 398.

- UI (bottom filter strip): Applied full Cinematic Blue treatment to `BottomFilterColumnsView` (the 4-column LIBRARY / COLLECTIONS / RATING / TAGS area under the grid/list).
  - Whole strip: `.appFilterStrip()` (subtle glass + appSurface + top divider line) for cohesive bottom chrome.
  - Column separators: thin `Color.appDivider` lines instead of stock Dividers.
  - Section headers: bold left blue accent bar (matching detail pane) + `Color.appAccent` text.
  - All rows, counts, badges: semantic `appTextPrimary/Secondary/Tertiary`, `appSurface` capsules, `AppSpacing`/`AppRadius`.
  - Selection states: `Color.appAccent.opacity(0.22)` rounded rects (consistent with grid/list).
  - Rating stars: cleaned up (no more colorScheme ternary).
  - Tag rename field and New Tag sheet: surfaced with app tokens.
  - "New Collection"/"New Tag" actions and empty states use `appTextSecondary/Tertiary`.
  - Lists tinted with `appAccent`.
  - Build 395.

- Bugfix (list view): "Go to top" now lands the first row *flush* under the column headers with no remaining gap. After the prior fix you could still wheel the mouse ~3-4 px further to tuck the row a little higher.
  - Root cause of residual gap: the previous overlap calculation converted whole `headerView`/`clip` *frames* into `NSScrollView` coordinates. Small differences in borders, separators, intercell spacing, and SwiftUI Table wrappers produced a 3-4 pt error in the computed intrusion.
  - Precise fix in `ScrollCommandHandler`:
    - `scrollListToAbsoluteTop`: after `scrollRowToVisible(0)`, convert only the *bottom edge point* of `table.headerView` (`NSPoint(x:0, y: bounds.maxY)`) directly into the `NSClipView` using `convert(_:to:)`.
    - Solve for the clip origin that places `rowRect.minY` exactly at that local "under-header" Y in the clip: `targetY = rowRect.minY - headerBottomLocalY_inClip`.
    - `reflectScrolledClipView`, then immediately call a new `correctListFirstRowUnderHeader(...)` helper that re-measures the same mapping and applies a micro-nudge if `|currentY - desiredY| > 0.25`.
    - The existing re-application timers (async + 80 ms) keep calling the full routine so any later layout/selection-visible adjustments are also corrected.
  - Grid mode and non-`.top` commands unchanged.
  - Build 394.

- Bugfix (list view): "Go to top" (⌘↑ or the top button) now positions the first row fully visible directly beneath the column headers (no longer half-hidden).
  - Initial attempt (y=0 for list .top) was insufficient. Even with document y=0 as the top of row 0, the `NSScrollView` clip view frame can intrude a few points under the `NSTableHeaderView` that the scroll view places for a SwiftUI `Table`. Targeting y=0 therefore parked the top sliver of row 0 behind the header.
  - Real fix in `ScrollCommandHandler`:
    - For `.top` + list mode: find the dominant `NSTableView`, call `scrollRowToVisible(0)`, derive `targetY` from `rect(ofRow: 0).minY`.
    - Measure the actual overlap: convert `table.headerView` and the content clip frames into the scroll view's coordinate space; `overlap = max(0, headerRect.maxY - clipRect.minY)`.
    - Compensate: `targetY -= overlap`. This places document row-top slightly "above" the clip top so it lands exactly at the visual bottom edge of the header.
    - Schedule two follow-up reapplications (immediate async + 80 ms) because SwiftUI/AppKit may run additional layout/selection-visibility scrolls that would otherwise re-obscure the first row.
  - Non-top commands and grid mode unchanged.
  - Build 393.

- Bugfix: Sorting the list view by the "Plays" column now correctly sorts by numeric play count.
  - Root cause: `VideoSort` enum (used by both the toolbar Sort menu and the fast custom sorter in `recomputeFilteredVideos`) had no `playCount` case.
  - `VideoSort.from(keyPath:)` fell back to `.dateAdded` whenever `\Video.playCount` (or `sortablePlayCount`) was passed from the Table's `sortOrder`.
  - `sortByTableOrder` therefore sorted by date added (or previous sort) instead of plays.
  - Fix: Added `.playCount` to `VideoSort`, implemented `comparators()` / `from(keyPath:)`, and the corresponding case in `sortByTableOrder`.
  - Added `var sortablePlayCount: Int` on `Video` for consistency.
  - Updated the Plays `TableColumn` (value keypath) to use `\.sortablePlayCount`.
  - "Plays" is now available as a sort in the list column header click and in the toolbar Sort menu.
  - Build 390.

- UI (list view): Applied Cinematic Blue treatment to `LibraryListView` rows for parity with grid.
  - Name column: thumbnails now use `.appMediaFrame` (small radius) + dark surface.
  - Larger popover thumbnails also framed.
  - Rename TextField inside list uses `appSurface` + `appAccent` stroke.
  - Filename text uses `appTextPrimary`.
  - Subtitles indicator pill uses `appAccent` background.
  - All data columns updated to semantic `Color.appTextSecondary` / `appTextTertiary`.
  - Resolution column now shows a small styled pill (dark surface + blue accent) for visual consistency.
  - Table tinted with `Color.appAccent` for blue-leaning selection/hover.
  - Consistent use of `AppSpacing`, `AppRadius`, and caption fonts.
  - Build 389.

- UI (grid cells): Applied Cinematic Blue treatment to `VideoGridCell`.
  - Now uses `.appVideoGridCell(...)` (backed by `.appCell`) for selection (blue-tinted fill + accent border) and hover states.
  - Thumbnail area backed by dark `appSurface` + `.appMediaFrame` (neutral subtle border).
  - Duration badge uses `appBadgeBackground`.
  - All text uses semantic `appTextPrimary/Secondary/Tertiary`.
  - Resolution pill styled as dark surface + blue accent.
  - File size and labels use design tokens.
  - Rename field inside grid uses `appSurface` + `appAccent` stroke.
  - Placeholder uses `appSurface` + tertiary icon.
  - Consistent `AppSpacing` / `AppRadius` and `Font.appCaption*` throughout.
  - Added size-aware rounding support in the grid cell style (`appCellWithRadius`).
  - Build 388.

- UI (detail pane): Removed prominent blue border from the filmstrip/thumbnail/player container. It now uses a dark blue surface background (Color.appSurface) matching the style and treatment of the Details, Custom, Rating, and Tags cards, with only a subtle neutral divider stroke. Inner frames also use neutral strokes.
- UI (detail pane, aggressive): Much stronger cinematic treatment on filmstrip/thumbnail + details data.
  - New `.appHeroPreview()` for the main preview area (dark blue surface matching the data cards, subtle divider stroke only).
  - `.appMediaFrame()` on preview imagery updated to neutral (no blue accent).
  - `.appDetailCard()` (stronger than previous subtle section) used on Details + Rating/Tags blocks with thicker blue strokes and more lift.
  - Section headers now have a bold left blue accent bar + uppercase labels on metadata rows for scannability.
  - Title area given a subtle surface treatment. Resize handle now has a visible blue grip.
  - Metadata rows have more weight (medium weight values, tighter hierarchy).
  - Stronger visual separator between the two data columns.
  - Picker bar integrated into the hero container with blue tint.
  - Left blue accent bars added to all section headers (Details, Custom, Rating, Tags).
  - Metadata rows made more scannable (uppercase labels, medium weight values).
  - Build 385.

## 0.14.1 (378) - 2026-06-27

- videomaster-playback-test pass: reviewed full checklist against implementation; fixed list view not receiving explicit centered scroll re-anchor after leaving detail-pane playback (now sets scrollToVideoId for both grid and list on exit).

## 0.14.0 (376) - 2026-06-27

- Foundation and agent workflow release:
  - Added `AGENTS.md`, `ROADMAP.md`, `SKILLS.md` as the core foundation documents.
  - Reconciled build/deploy rules; created `.cursor/rules/release-workflow.mdc` for VideoMaster.
  - Created `videomaster-playback-test` skill.
  - Retired `IMPROVEMENTS.md` and `DEVELOPMENT_SUMMARY.md` (key ideas folded into `ROADMAP.md`).
  - Cleared `docs/USER_GUIDE.md` (full guide deferred until closer to production release).
  - Introduced live `CHANGELOG.md` process: agents maintain high-level changes in `## Unreleased` on every commit; content is consolidated into versioned release entries on release.
  - Strengthened rules and agent instructions for commit discipline (always `git add -A` for tracked + untracked files) and requiring releases to commit all completed work.

## 0.13.0 (375) - 2026-06-16

- floating overlay playback + playback-mode control

## 0.12.1 - 2026-06-15

- fix grid scroll position after inline playback

## 0.12.0 - 2026-06-15

- library performance overhaul and stability fixes

## 0.11.0 - 2026-06-14

- navigation controls, consolidated view bar, move + convert fixes

## 0.10.0 - 2026-06-07

- in-app re-encoding, Recently Converted filter, and playback UX

## 0.9.0 - 2026-05-08

- library polish, subtitles, and playback UX

## 0.8.1 (281) - 2026-04-02

- Release VideoMaster 0.8.1 (build 281)

## 0.8.0 - 2026-03-27

- Release VideoMaster 0.8.0

## Earlier releases

Follow the same pattern. See git tags (`v0.7.x` and prior) and their associated commit messages for the exact summaries and (where recorded) build numbers at the time.

---

*This file is the source of truth for "what shipped in which build" and for the running history of changes between releases.*