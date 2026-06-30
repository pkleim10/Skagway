# Curated Wall – Readiness Checklist
**Branch:** `feature/curated-wall`  
**Date:** 2026-06-28  
**Goal:** Confirm we have everything needed to start implementation with confidence.

This checklist is based on the fresh audit (`Fresh_Workspace_Audit_2026-06.md`), the saved mockups in `docs/images/workspace-audit-2026-06/`, and the current main-branch architecture.

---

## A. References & Environment

- [x] On clean `feature/curated-wall` branch created from main
- [x] `Fresh_Workspace_Audit_2026-06.md` present and contains detailed Curated Wall section
- [x] Refined mockups saved locally:
  - `curated-wall-full-window-mock.png`
  - `curated-wall-cards-refined-mock.png`
  - `curated-wall-inspector-detail-mock.png`
  - `curated-wall-inspector-multiselect-mock.png`
  - Plus the earlier `curated-wall-inspector-mock.png`
- [x] User has reviewed the latest mockups (including the full-window mock currently open) and we are using them as the primary reference.

**Answers:**
1. Yes, reviewed. No major changes requested at this time. We will use the refined mockups (`curated-wall-full-window-mock.png`, `curated-wall-cards-refined-mock.png`, `curated-wall-inspector-detail-mock.png`, `curated-wall-inspector-multiselect-mock.png`) as the visual target.
2. No. The new refined mockups take precedence over the older wireframes. Older wireframes can be kept for reference but are not authoritative.

---

## B. High-Level Model

**Current architecture (main):**
- Persistent `ResizableBrowserDetailSplitView` (left browser + right detail)
- Optional vertical split in browser for bottom filter strip
- `VideoDetailView` = large hero (thumbnail/filmstrip/player) on top + scrollable metadata area below

**Target from Curated Wall mockups:**
- Left/middle = elegant "Wall" (gallery-style browsing surface that stays visible)
- Right = dedicated Inspector panel
- Inspector contains its own medium-tall hero strip (still or filmstrip) + organization tools
- Clicking the wall populates the inspector without hiding the wall
- Larger viewer experience is invoked from the inspector hero

**Split behavior (confirmed by user):**
- The division between the Wall (browser) and Inspector is **resizable** via a movable splitter (thin divider).
- Subject to "reasonable limits" — minimum widths on both sides to keep the UI usable and visually balanced (e.g. wall never narrower than enough for 3–4 attractive cards; inspector never narrower than needed for its hero + sections). Default proportions will be taken from the mockups.

**Decisions needed:**
- [x] The wall/inspector split is resizable (movable thin divider) within reasonable min/max width limits (confirmed 2026-06-28).
- [x] We are evolving the existing browser + detail split model (single persistent model with resizable split, similar to current main but with refined visual treatment).
- [x] The Inspector hero is intentionally **medium height inside the inspector** (more balanced with the organization tools below, per the refined mockups).
- [x] The Wall remains the primary browsing surface even when an item is selected.

**Answers:**
3. Re-thought / de-emphasized for this variant. The mockups focus on a clean wall + inspector experience. The 4-column bottom filter strip (Library/Collections/Rating/Tags) will be hidden or moved to a secondary/collapsible location (e.g. accessible via a "Filters" button or top bar) rather than always visible under the wall.
4. Single persistent model. No top-level Browse/Focus mode switcher for Curated Wall. The experience is one cohesive "Wall + Inspector" view.

---

## C. Layout & Visual Treatment

### Wall / Browsing Surface
- [ ] Card treatment should be more elegant/gallery-like than current `VideoGridCell` (lighter metadata, better framing, more breathing room)
- [ ] Selection state: soft blue ring + small checkmark in thumbnail (per mockup)
- [ ] Metadata under cards: short title + date + tiny stars (minimal)
- [ ] Density: noticeably less dense than current grid

**Answers:**
5. Target 5 columns at typical window widths (as shown in the full-window mockup), with good breathing room. Allow the number to adjust responsively down to 3–4 at smaller widths, and up if the window is very wide.
6. Regular grid with fixed gaps (for predictability and performance), but with more generous spacing and elegant card framing than the current grid. Not fully "justified" like a photo wall app.
7. The Wall replaces the current dense grid view for this variant. We can keep a simple "View mode" affordance later if needed, but the primary browsing surface is the refined Wall. List view can remain available as a secondary option if desired, but the visual target is the Wall.

### Inspector Panel (right side)
From the refined mockups, the vertical order and treatment is:

1. Hero strip (medium-tall, ~35-40% of inspector height)
   - Still or filmstrip
   - Subtle centered play overlay
   - Small duration badge bottom-right
   - Toggle (Still / Filmstrip) top-right of hero

2. Title block
   - Large editable title
   - Dimmed full path or "in folder" link
   - Quick actions row (icons): Play (detail/overlay/full), Reveal, Quick Tag, Quick Rate

3. Core Facts (tight, low visual weight)
   - Resolution | Duration | File Size
   - Codec + fps | Date Added | Last Played + Plays
   - Subtitles (filename when loaded, or Yes/No + Load action)

4. Rating (prominent, own section with blue left accent)
   - Large stars + Clear button

5. Tags (blue accent + removable chips + Add tag pill)

6. Notes (first-class, reasonably tall area with character counter)

7. Custom Metadata (clear section)

8. Technical footer (low weight)

**Answers:**
8. Medium-tall hero strip, approximately 35-40% of the Inspector panel height (as shown in the inspector-detail mockup). This is deliberately more balanced with the tools below it than the current very large dominant hero.
9. Compact horizontal strip (or tight 3-column row) for the core facts, matching the refined mockups. Lower visual weight than the current two-column grid.
10. Design new or extended treatments for this variant:
    - New `appWallCard` style for the browsing cards (more elegant, gallery feel).
    - Refined or new `appInspectorHero` and `appInspectorSection` for the right panel to achieve the cleaner vertical stacking and stronger blue accents seen in the mockups.
    We will reuse existing tokens (colors, radii, spacing) where possible.
11. Top-right of the hero strip (as shown in the mockups), as a small segmented control or tabs: "Still / Filmstrip".

---

## D. Interaction & Playback Model

**Key behaviors from plan + mockups:**
- Single-click on wall item → selects it and populates the Inspector (wall stays visible)
- Double-click or play button in hero → opens a larger viewer experience
- Playback modes (detail-pane inline, overlay, fullscreen) must still be available
- Resume banner logic must continue to work
- Filmstrip click-to-seek must work when the hero is in filmstrip mode

**Answers:**
12. Replace the hero in-place with the player by default (similar to current detail-pane inline playback). Overlay and Fullscreen remain available via the quick actions row or keyboard shortcuts.
13. Yes. Provide a "maximize viewer" / expand affordance (e.g. icon in the hero or title area) that gives the inspector hero significantly more vertical space (or temporarily collapses/hides the wall). This supports focused viewing without leaving the Curated Wall model.
14. The inspector should immediately reflect multi-select state when items are selected on the wall (show aggregated "X videos selected", bulk-capable controls for rating/tags/notes). An explicit "bulk edit" action is not required, but clear visual distinction between single and multi-select states in the inspector is important (as shown in the multiselect mockup).

---

## E. Preservation of Existing Capabilities (Mandatory)

The plan already has a detailed mapping. All of these will be preserved (they may be presented or accessed differently, but must remain fully functional):

- [x] Filmstrip generation, display, and click-to-seek
- [x] Thumbnail / Filmstrip toggle
- [x] All three playback modes (detail-pane inline, overlay, fullscreen)
- [x] Resume playback position + auto-resume banner
- [x] Sidecar subtitles (discovery, display, selection)
- [x] Rating (single and bulk)
- [x] Tags (create, apply, remove, filter by)
- [x] Notes (first-class in this variant)
- [x] Custom metadata (all types)
- [x] Collections (rule-based filtering + "Add to Collection")
- [x] Multi-select + bulk operations
- [x] Search (FTS + live filtering)
- [x] Advanced filters (rating, tags, date, duration, corrupt, duplicates, missing, etc.)
- [x] Re-encoding workflow
- [x] Keyboard navigation, surprise-me, scroll commands, etc.
- [x] Layout persistence (split widths, etc.) – at least for the browsing surface and inspector proportions within limits

**Answers:**
15. Treat Notes as a first-class feature in the Inspector for this variant (tall, comfortable text area with character counter, as shown in the mockups). We will implement simple per-video persistence for now (UserDefaults or a lightweight store) with the option to promote it to a proper database field later.
16. For the initial implementation, we are open to de-emphasizing the always-visible 4-column bottom filter strip (see answer to #3). Everything else (playback modes, filmstrip, resume, subtitles, collections, custom metadata, re-encoding, keyboard commands, etc.) should remain fully available, even if accessed through the Wall + Inspector UI.

---

## F. Technical & Architecture

- [ ] We will evolve the existing `ResizableBrowserDetailSplitView` + right detail pane model
- [ ] The left side will still support `ViewMode` (grid vs list) or will the Wall replace the grid view?
- [ ] Do we need new or extended layout persistence for inspector hero height vs metadata area?
- [ ] Inspector will be a refactored or new component (not just styling changes to `VideoDetailView`)
- [ ] Wall cards will likely be a new or heavily modified `VideoGridCell` variant for better gallery aesthetics
- [ ] Design system: we will probably need a few new modifiers (e.g. `appWallCard`, `appInspectorHero`, `appInspectorSection`)

**Answers:**
17. Hide it from the main view for this variant (see #3). It can be made available via a "Filters" button in the top bar or a sheet if needed. The "showFilterStrip" toggle can be repurposed or removed for Curated Wall.
18. Yes. We will extend or create a simple dedicated storage for Curated Wall layout (split width + inspector internal proportions such as hero vs. metadata height) so the variant can have its own sensible defaults while still allowing user adjustments. We can reuse much of the existing `LayoutParams` infrastructure.

---

## G. Build & Testing Strategy

From previous variants (Library Desk → VMLibrary.app):

**Answers:**
19. Yes. Build it as a separate app (e.g. `VMCurated.app`) for side-by-side testing, following the same approach used for VMLibrary.
20. Yes, follow the exact same discipline:
    - Bump `CURRENT_PROJECT_VERSION` in project.yml
    - `xcodegen generate`
    - Build Release
    - Rename the built .app to the variant name
    - Install to /Applications
    - Clean stray copies (DerivedData + global)
    - Announce the deployed version (e.g. "VMCurated 0.15.0 (build XXX) [Release]")

---

## H. Scope for First Implementation Pass (MVP)

Proposed minimal slice that lets us see the concept:
- Refined wall cards (selection, hover, lighter metadata)
- Inspector restructured to match the vertical mockup order
- Hero strip inside the inspector (with toggle and play affordance)
- Basic title + facts + rating + tags + notes + custom fields in the inspector
- Clicking wall item populates inspector
- Playback from inspector hero works (at least one mode)
- All existing data and filtering continues to work on the wall

**Answers:**
21. Yes, the proposed MVP slice is acceptable for the first build:
   - Refined wall cards
   - Inspector restructured to the vertical order in the mockups
   - Medium hero strip inside the inspector
   - Core fields (title, facts, rating, tags, notes, custom)
   - Selection populates inspector
   - At least one playback path from the hero works
   - Existing filtering/search/data works on the wall
22. Nothing additional is strictly required for the very first build beyond the MVP slice. Priority after the first build will be polishing the card aesthetics, ensuring the resizable split respects limits, and multi-select bulk experience in the inspector.

---

## I. Open Questions / Risks (Post-Answers)

- Performance of the more elegant (potentially less dense) wall at large library sizes — to be validated during implementation.
- The current bottom filter columns (4-column) will be de-emphasized for this variant (see answers #3 and #17).
- Top library nav bar (search, sort, count, view controls) will be retained and refined to fit the Wall aesthetic.
- We will reuse the Cinematic Blue tokens heavily and extend with a small number of new card/inspector modifiers (`appWallCard`, `appInspectorHero`, etc.).

All other major decisions are locked in the answers above. Any remaining details will be handled during implementation with quick feedback.

---

## Summary – All Questions Answered

All numbered questions (1–22) have been answered in this session (2026-06-28). Key decisions:

- Single persistent model (no Browse/Focus switcher).
- Resizable split (thin divider) between Wall and Inspector, with reasonable min/max limits.
- Inspector has a medium hero strip (~35-40% of its height) + vertical organization sections.
- Wall is the primary elegant browsing surface (refined cards, ~5 columns target).
- Bottom filter strip de-emphasized/hidden in main view.
- Notes treated as first-class.
- Side-by-side build as a separate app (following the established discipline).
- MVP scope as proposed is acceptable for first build.

The checklist is now fully populated with answers. We can proceed to implementation.

**Next immediate steps (recommended):**
- Create a dedicated CuratedWall plan document if desired (or evolve the existing audit doc).
- Start with high-impact pieces: wall card styling + inspector vertical restructuring.
- Follow normal build discipline after every meaningful change.

**Current status:** All readiness questions answered. Ready to begin building.