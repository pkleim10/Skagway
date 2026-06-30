# Dual Mode – Implementation Plan

**Reference:** Dual Mode wireframe (`DualMode-82e55a9e-....png`) posted 2026-06-28.

**Goal:** Implement a deliberate **Browse / Focus** mode switch that changes the primary workspace experience in VideoMaster.

This is the second major workspace variation we are exploring (after Library Desk on `feature/library-desk`).

---

## 1. Understanding of "Dual Mode" from the Wireframe

The wireframe presents two intentionally different working modes that the user switches between:

### Browse Mode (left side of the "switch intention")
- **Purpose**: "Scan. Filter. Select."
- Dense, information-rich grid for rapid scanning and discovery.
- Visible multi-select with checkboxes on every card.
- Prominent bulk action toolbar: Add Tag, Set Rating, Add to Collection, Export, Delete.
- Powerful horizontal filter bar at the top with multiple dropdowns (All Tags, All Ratings, All Dates, All Durations, All Sources, More Filters).
- Search field.
- Goal: Power through many items quickly, apply broad filters, make selections, perform operations on groups.

### Focus Mode (right side of the "switch intention")
- **Purpose**: "View. Organize. Refine."
- Large, elegant viewer as the hero element.
- Full-featured Inspector docked or prominent (Rating with stars + Clear, Tags as editable chips, Notes with context and character counter).
- More breathing room, less density.
- The current selection is the star of the show.
- Goal: Deep engagement with one (or a small curated set of) video(s) — watch carefully, rate thoughtfully, build rich metadata and notes.

### Mode Switcher
- Prominent segmented control at the very top: **Browse** | **Focus**.
- Keyboard hints: "Switch modes: B (Browse) / F (Focus)".
- Visual treatment that makes the current mode very clear.
- Label underneath: "Different modes. Different focus." + "SWITCH INTENTION".

### Supporting UI
- Left sidebar explains the value of each mode.
- Bottom of the main area has zone labels reinforcing the current intention ("SCAN & SELECT (BROWSE MODE)" vs "VIEW & ORGANIZE (FOCUS MODE)").
- The grid in Browse uses a more compact card treatment with visible selection state.
- Inspector appears strongly associated with Focus (though it may still be useful in Browse for quick edits).

**Core Philosophy**
This is not just "make the detail pane bigger or smaller."  
It is a **mode switch that changes the user's primary task and the density/emphasis of the entire interface**.

---

## 2. How This Differs from Current VideoMaster and Library Desk

| Aspect                    | Current VideoMaster (main)          | Library Desk (prototype)             | Dual Mode (target)                          |
|---------------------------|-------------------------------------|--------------------------------------|---------------------------------------------|
| Workspace model           | Persistent split (browser + detail) | Biased "desk" layout with docked inspector | Explicit Browse vs Focus modes             |
| Mode switch               | No high-level workspace mode        | None                                 | Top-level Browse / Focus toggle            |
| Density                   | Medium                              | Biased toward viewer                 | Browse = dense/scannable; Focus = spacious |
| Multi-select & bulk       | Supported but secondary             | Secondary                            | First-class in Browse (checkboxes + toolbar) |
| Viewer prominence         | Balanced with list                  | Large hero                           | Dominant only in Focus                     |
| Inspector                 | Part of detail pane                 | Docked below viewer                  | Prominent / first-class in Focus           |
| Intention signaling       | Implicit                            | "Library Desk" branding              | Explicit "Switch Intention" language       |

Dual Mode should feel like the app "changes personality" when you flip the switch.

---

## 3. High-Level Requirements & Scope

**Must have for a convincing implementation**
- Clear, prominent Browse / Focus switcher (custom segmented control or strong visual treatment).
- Keyboard support (B / F, and possibly ⌘1 / ⌘2 or similar).
- In **Browse**:
  - Dense grid with clear multi-select checkboxes.
  - Bulk action bar that appears when items are selected.
  - Rich filter bar (many quick filters visible).
- In **Focus**:
  - Large viewer area (reuse or enhance existing player framing).
  - Strong Inspector surface (Rating, Tags, Notes at minimum).
  - Possibly a reduced or contextual list (e.g. "selection strip" or "recently browsed").
- Mode preference should be persisted per user (or per library session).
- Selection state carries across modes (if you select items in Browse, you should be able to switch to Focus and work on them).
- Reasonable animation or transition between modes (not jarring).
- The Cinematic Blue design language must be maintained.

**Nice to have / future**
- Different default split widths or pane heights per mode (via LayoutParams or new mode-specific storage).
- Mode-specific empty states and guidance.
- "Focus on current selection" behavior when entering Focus.
- Ability to temporarily "pin" items for Focus work while still having a scan strip.

---

## 4. Architectural Considerations

### 4.1 Workspace Mode State
- Add a new enum, e.g.:
  ```swift
  enum WorkspaceMode: String, CaseIterable {
      case browse, focus
  }
  ```
- Store in `LibraryViewModel` (or a new dedicated observable) + persist via UserDefaults or layout prefs.
- Drive major layout decisions from this value.

### 4.2 Layout Strategy Options (to discuss)

**Option A – Two different root compositions**
- Browse root: dense grid + top filters + bulk bar + optional slim inspector.
- Focus root: large viewer + rich inspector + optional thin context strip.
- Use a top-level switch in `LibraryContentView` or a new `DualModeHostView`.

**Option B – One flexible layout with heavy conditional chrome**
- Keep the existing split infrastructure but heavily mutate:
  - Hide/show bottom filter strip.
  - Change grid density / card size.
  - Promote or collapse the detail pane.
  - Swap in different header toolbars.
- Potentially easier for state continuity, harder to get the "completely different feel."

**Option C – Hybrid**
- Shared data and selection model.
- Significantly different view hierarchies for the main content area.
- Shared chrome (top mode switcher, global search, status bar).

**Recommendation for discussion**: Start with a hybrid that reuses as much as possible (grid cells, inspector components, filters) but allows the *arrangement and visual weight* to change dramatically.

### 4.3 Selection & Multi-Select
- Browse benefits from strong multi-select.
- Focus is often single-item (or small curated set).
- We need clear rules:
  - Can you have multiple items selected when entering Focus?
  - Does Focus show a "filmstrip" or "selected set" strip?
  - Bulk actions should probably be disabled or de-emphasized in Focus.

### 4.4 Filters
- The wireframe shows many filter dropdowns. Some can reuse existing sidebar filters + new ones.
- In Browse, surface more filters visibly.
- In Focus, filters may be secondary or collapsed.

### 4.5 Playback
- How does inline playback behave differently per mode?
- In Focus, the large viewer should be the default place for playback.
- In Browse, overlay or small inline might be preferred to keep scanning flow.

### 4.6 Left Sidebar / Guidance
- The wireframe has explanatory text for each mode.
- We can make a mode-aware left panel or keep a simplified version of the current sidebar that highlights the current intention.

---

## 5. Proposed Phased Plan

### Phase 0 – Foundations
- Define `WorkspaceMode` enum and wire it into `LibraryViewModel`.
- Add persistence.
- Add a high-quality `DualModeSegmentedControl` (or reuse/extend `AppSegmentedControl`) at the top of the library area.
- Add keyboard handling (B / F).

### Phase 1 – Browse Mode Polish
- Make the grid denser / more scannable when in Browse.
- Add visible checkboxes + multi-select UX improvements.
- Surface or enhance the bulk action toolbar.
- Tune the top filter bar to feel like the wireframe (many quick filters visible).

### Phase 2 – Focus Mode
- When in Focus, give the viewer area significantly more space and visual weight.
- Promote / redesign the Inspector (make Rating, Tags, Notes feel primary).
- Consider a "context strip" or reduced grid on the side or bottom for the current selection set.
- Adjust typography, spacing, and card treatments to feel more "elegant and focused."

### Phase 3 – Mode Transitions & State
- Smooth(ish) transitions or layout swaps when switching.
- Preserve scroll position, selection, and filter state.
- Decide on layout persistence (separate LayoutParams for each mode?).

### Phase 4 – Details & Refinement
- Mode-specific empty states and onboarding text.
- "Switch intention" labeling and micro-copy.
- Polish the filter dropdowns and bulk actions to match wireframe spirit.
- Test with real libraries for performance (dense Browse grid).

### Phase 5 – Optional / Stretch
- Different default grid sizes per mode.
- "Focus session" concept (temporary set of items to work on).
- Animation between modes.
- Remember last-used mode.

---

## 6. Reusable vs New Components

**Likely reusable / adaptable**
- `VideoGridCell` (with density variants or modifiers)
- Existing filter logic (`selectedTagIds`, `selectedRatingStars`, sidebar filters, search)
- `VideoDetailView` / inspector sections (Rating, Tags, Notes)
- `AppSegmentedControl` style
- Thumbnail / filmstrip generation
- `LibraryViewModel` filtering engine (already very capable)

**Likely new or heavily modified**
- Top mode switcher chrome
- Bulk action toolbar component
- Browse-specific grid container / density handling
- Focus-specific viewer + inspector layout
- Possibly a new "selection strip" or contextual list for Focus
- Mode-aware layout parameter storage

---

## 7. Open Questions for Discussion (please answer / prioritize)

1. **Layout radicalness**: How far are we willing to go? Should Browse and Focus feel like two almost-different apps, or two strong configurations of the same underlying split?
2. **Focus mode grid/list**: In Focus, do we hide the grid entirely, collapse it to a thin horizontal strip, or keep a small vertical list of the current "working set"?
3. **Multi-select in Focus**: Should Focus allow multi-select at all, or force single-item focus?
4. **Left sidebar**: Should it change content or prominence based on mode, or stay relatively stable?
5. **Playback default**:
   - Browse → prefer overlay or small preview?
   - Focus → large viewer is the only player?
6. **Filter visibility**: In Focus, do advanced filters move to "More Filters" or stay accessible?
7. **Persistence**: Remember the last mode used? Per-library or global?
8. **Name**: Are we calling the modes "Browse" and "Focus" in the UI, or something else (e.g. "Library" / "Studio", "Scan" / "Curate")?

---

## 8. Success Criteria

- A user can clearly tell which mode they are in at a glance.
- Switching modes feels like changing tools for a different job, not just resizing panes.
- Browse feels fast and powerful for working with many videos.
- Focus feels calm, spacious, and excellent for deep work on individual videos.
- All core functionality (playback, rating, tagging, notes, filtering, selection) remains available and consistent in both modes.
- Performance remains good in the dense Browse grid.

---

## 9. Files Likely to Touch (initial guess)

- `Views/ContentView.swift` (or a new host)
- `ViewModels/LibraryViewModel.swift` (WorkspaceMode + related state)
- New or updated layout model (possibly extend `LayoutParams`)
- New components:
  - `DualModeSwitcher.swift`
  - `BrowseGridContainer.swift` or modifiers
  - `FocusViewerInspector.swift`
  - `BulkActionBar.swift`
- `Views/Library/LibraryGridView.swift` + `VideoGridCell`
- `Views/Detail/VideoDetailView.swift` (inspector parts)
- Design system tweaks if needed for density variants

---

## 10. Next Steps (after you review this plan)

1. You review / correct / expand this plan.
2. We agree on high-level architecture choices (especially Option A/B/C and how radical the mode switch should be).
3. We decide on the open questions above.
4. Then we start implementation in small, reviewable chunks with builds (following the usual discipline).

---

**Status**: Planning phase. No major implementation yet on this branch.

Branch: `feature/dual-mode`

Please give me your thoughts, corrections, and priorities so we can refine this before writing code.
