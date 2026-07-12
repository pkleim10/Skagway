# Library Desk – Detailed Visual Implementation Plan

**Reference:** The provided "VideoDesk / Library Desk" screenshot (dark cinematic UI with clear zoned layout).

**Goal:** Make `VMLibrary.app` (the `feature/library-desk` build) match the reference as closely as possible in:
- Overall layout and visual zones
- Sidebar structure and selection treatment
- Search + Filters header (exact element layout, pills, dropdowns)
- Grid card treatment (shape, overlays, typography, spacing, selection)
- Viewer + Inspector presentation
- Typography, spacing, color weight, and "cinematic but clean" feel

This plan is based on direct analysis of the reference image + current state of the prototype (build ~413).

---

## 1. High-Level Layout & Zones (from reference)

```
+-----------------------------------------------------------------------+
| [VideoDesk]                                  SEARCH + FILTERS   VIEWER |
| ┌──────────────┐  ┌──────────────────────────────────┬──────────────┐ |
| │ Library Desk │  │ Search pill   [All][Fav]...[More]│  Large       │ |
| │ Collections  │  │ 4,256 videos   Sort ▼  [Grid][List]│  Player      │ |
| │ Smart Bins   │  │                                  │  + controls  │ |
| │ Tags         │  │  ┌────┐ ┌────┐ ┌────┐ ┌────┐    │              │ |
| │ Ratings      │  │  │Card│ │Card│ │Card│ │Card│    │  Metadata    │ |
| │ Trash        │  │  └────┘ └────┘ └────┘ └────┘    │  + RATING    │ |
| │              │  │                                  │  + TAGS      │ |
| │ LIBRARY      │  │  (more rows...)                  │  + NOTES     │ |
| │ • All Videos │  │                                  │              │ |
| │ • Favorites  │  └──────────────────────────────────┴──────────────┘ |
| │ • Recent     │                                                       |
| │ • Imports    │  (bottom labels: "BROWSE GRID"   "INSPECTOR: RATING / TAGS / NOTES") |
| └──────────────┘                                                       |
| Storage bar + icons                                                   |
+-----------------------------------------------------------------------+
```

- **Left sidebar**: Fixed narrow nav (~200 px). Distinct header, primary nav, LIBRARY section, footer.
- **Browse area**: Header ("SEARCH + FILTERS") + content (grid or list) + bottom zone label.
- **Viewer area**: "VIEWER" header + large player + docked Inspector below + bottom zone label.
- Strong visual separation between the three main vertical bands (sidebar / browse / viewer).
- Blue accent used consistently for active/important elements and small left "accent bars" on section labels inside the inspector.

---

## 2. Left Sidebar – Exact Anatomy

**Header**
- Icon (film-strip / stacked rectangles style) + "VideoDesk" (15pt semibold).
- Slight surface lift behind the header.

**Primary Navigation**
- Vertical list with good rhythm (~28-32px row height).
- Each row: icon (left) + label.
- "Library Desk" selected state: rounded pill background using a blue-tinted surface (stronger than hover). Text and icon become accent blue or high-contrast white.
- Other items use secondary text color. Optional small count badges on some (Collections, Tags).

**LIBRARY Section**
- Small blue uppercase label "LIBRARY" (10-11pt semibold).
- 4 main rows:
  - All Videos (icon + count)
  - Favorites
  - Recent (or "Recently Added")
  - Imports
- Row treatment: icon + name left, count right-aligned, subtle hover/selected state that matches the primary nav selected style when active.

**Footer**
- Thin divider.
- Storage section: "Storage" label + horizontal progress bar (blue fill) + "X TB / Y TB" text.
- Bottom row: small gear icon (settings) and person icon (account/profile), right or left aligned.

**Current Gaps (prototype)**
- Selection treatment on "Library Desk" is too subtle.
- "LIBRARY" section rows need more visual weight and exact icon + count alignment.
- Storage bar is present but styling is rough.
- Icon for "VideoDesk" header and some nav items need to be closer (current uses generic SF Symbols).

---

## 3. Browse Area Header – "SEARCH + FILTERS"

**Label**
- "SEARCH + FILTERS" in small (10-11pt), semibold, accent blue. Positioned above the search row, spanning the width or left-aligned.

**Search Row**
- Wide rounded pill search field.
- Left: magnifying glass (tertiary color).
- Placeholder: "Search videos..." (or very close).
- Right: clear (X) button when text present.
- Focus ring: subtle blue (stronger than unfocused border).

**Filter Chip Row (immediately below search)**
From left to right (exact order and style in reference):
1. "All" – solid blue pill (filled background, white or high-contrast text).
2. "Favorites", "Untagged", "Has Tags" – lighter / outline style pills (same height and rounding as "All").
3. Dropdown-style filter pills (chevron down):
   - "Date Imported"
   - "Any Duration"
   - "Any Resolution"
   - "More Filters"

These are all same-height, rounded, pill-shaped controls. They feel like a continuous filter toolbar.

**Right side of header (same row or just below)**
- Video count ("4,256 videos") – small, secondary text.
- Sort control: "Sort: Date Imported" or similar with chevron (menu or segmented).
- View mode toggle (grid icon active, list icon).
- Possibly a small "Save View" or view options button (visible in reference top-right of this zone).

**Current Gaps**
- Filter pill row is incomplete (missing the exact dropdown pills and "Untagged" treatment).
- "All" is not rendered as a distinctly filled blue pill when active in the same way.
- Count + sort + view controls are present but layout and typography need tightening to feel like one header bar.
- No "Save View" affordance yet.

---

## 4. Grid / Browse Content Treatment ("BROWSE GRID")

**Card Design (critical for look & feel)**
- Thumbnail image area with medium-large rounded corners (≈ 8-12px).
- Dark surface behind or around the image (subtle frame).
- Duration badge: small dark semi-transparent rounded rect in **bottom-right** of the thumbnail, white monospaced-ish text, tight padding.
- Favorite / star indicator: visible on cards (often lower-left of image area or as a small star overlay).
- Below the image (tight spacing):
  - Filename – medium weight, primary text, 1-2 lines.
  - Second line: date (and possibly resolution or size) in smaller secondary text.
  - Subtle rating stars (yellow) on the right of the meta line when present (small).

**Layout**
- Comfortable horizontal and vertical spacing between cards (≈ 12-16px).
- Typically 4 columns at the reference window width.
- The whole grid lives under the search/filter header with reasonable outer padding.

**Selection & Hover**
- Selected card has a clear blue ring/border (around the whole card or just the image frame) + possibly a slightly brighter/lifted surface.
- Hover gives a gentle surface lift or border.

**Current Gaps (VideoGridCell + LibraryGridView)**
- Duration badge position and styling is close but can be refined (size, opacity, exact font).
- Star placement and rating display under cards need to match the reference more precisely.
- Selection "pop" is present (blue ring) but weight and treatment should be compared directly to the image.
- Typography scale and line spacing under the image need review.
- Overall card surface treatment vs pure image + text.

---

## 5. Right Viewer + Inspector ("VIEWER" / "INSPECTOR")

**Viewer Header**
- "VIEWER" small blue label at top of the right column.

**Player Area**
- Large rounded video frame.
- Playback controls at the bottom of the frame (scrubber, play/pause, timecode, volume, settings, fullscreen). The reference shows a clean modern bar.

**Metadata Block (directly under player)**
- Title ("Alpine Morning") – larger, bold or semibold.
- One-line specs: resolution, fps, aspect, codec, duration, date/time – small, evenly spaced, secondary color. Separators are dots or thin vertical lines.
- Small info (i) and overflow (…) icons on the right.

**Inspector Subsections (labeled "INSPECTOR: RATING / TAGS / NOTES" at bottom)**
Each subsection uses a consistent pattern:
- Small blue vertical accent bar (left) + label in accent blue.
- Content:

  - **RATING**: 5 stars (filled yellow/gold for active). "Clear Rating" text button on the right.
  - **TAGS**: Removable tag chips (rounded, medium blue-gray surface, text + X). "+" button or pill to add.
  - **NOTES**: Contained text editor / text area. Sample text visible. Character counter bottom-right (e.g. "120 / 2000").

The inspector area has a slightly different (card-like) surface treatment from the pure player.

**Current Gaps**
- Player frame treatment and control bar styling.
- Metadata specs row formatting and density.
- Inspector subsection labels + blue accent bars are already partially implemented, but visual weight, star size, chip styling, and notes field need to match the reference.
- "INSPECTOR: ..." bottom label.

---

## 6. Typography (approximate sizes from reference)

- Zone headers ("SEARCH + FILTERS", "VIEWER", "LIBRARY", "INSPECTOR..."): 10–11 pt, semibold, accent blue.
- Sidebar nav labels: 13–14 pt.
- Card titles: 12–13 pt, medium to semibold.
- Card meta / date / specs: 10–11 pt, regular.
- Filter pills: ~11–12 pt.
- Search placeholder: 12–13 pt.
- Counts: 10–11 pt.
- Notes content: body / callout size.

Use system sans (or the closest the design system already approximates). Weight and color contrast are more important than exact font family.

---

## 7. Colors, Materials, and Tokens (reference-aligned)

Current design system is already very close:
- `appBackground`: deep navy
- `appSurface` / `appCard`: lifted dark surfaces
- `appAccent`: #3b82f6 (good match)
- `appTextPrimary` (white), `appTextSecondary` (#a1b0c9 range), `appTextTertiary`
- `appDivider`: low-opacity white

**Needed refinements / new tokens (or usage rules)**
- Stronger selected pill background for sidebar (e.g. `appAccent.opacity(0.18–0.25)` or a dedicated `appSelectedNav`).
- Filter pill "active" vs "inactive" variants.
- Duration badge background (currently `appBadgeBackground` – verify opacity).
- Star color is yellow (keep consistent).
- Subtle elevation or border on viewer player frame.
- Inspector subsection surface (slightly different from main background).

---

## 8. Spacing & Corner Radii Targets

- Sidebar row vertical padding: ~6–8 pt.
- Header padding: 8–12 pt.
- Card outer padding and gaps: 12–16 pt.
- Inside cards: tight (4–8 pt) between image and title, title and meta.
- Player and inspector cards: 10–12 pt radius.
- Filter pills and small controls: 12–16 pt radius (pill).
- Blue accent bars in inspector: 3–4 pt wide × 16–18 pt tall.

---

## 9. Current Prototype vs Reference – Gap Summary (as of build 413)

| Area                    | Status in Prototype                  | Gap vs Reference                              |
|-------------------------|--------------------------------------|-----------------------------------------------|
| Left sidebar header     | "VideoDesk" present                  | Icon + surface treatment need polish          |
| Primary nav selection   | Basic                                | Needs stronger blue pill treatment            |
| LIBRARY section         | Functional rows                      | Visual weight, icons, counts alignment        |
| Storage footer          | Basic bar + icons                    | Polish bar, typography, layout                |
| SEARCH + FILTERS label  | Present                              | Exact size/weight/placement                   |
| Search pill             | Good                                 | Focus ring + exact metrics                    |
| Filter chip row         | Partial (All + a few + "More")       | Missing exact pills + dropdowns + order       |
| Count + Sort + View     | Present but loose                    | Tighten into a cohesive header treatment      |
| Grid cards              | Reasonable                           | Duration badge, star, meta typography, selection ring |
| Viewer player frame     | Basic                                | Frame treatment + control bar fidelity        |
| Metadata block          | Partial                              | Specs line density and separators             |
| Inspector subsections   | Labels + accents + Notes exist       | Star size, tag chip style, notes field polish |
| Zone labels (bottom)    | Only a small marker text             | Add "BROWSE GRID" and "INSPECTOR: ..."        |
| Overall density/spacing | Close but not exact                  | Many micro-adjustments                        |

---

## 10. Phased Implementation Plan (Recommended Order)

**Phase 0 – Foundations (low risk)**
- Review / extend design tokens for sidebar selected nav, filter pill active state, duration badge, inspector subsection surface.
- Add or refine `AppRadius`, `AppSpacing` values if needed for exact match.
- Bottom zone labels ("BROWSE GRID", "INSPECTOR: RATING / TAGS / NOTES").

**Phase 1 – Sidebar Fidelity**
- Redesign `LibraryDeskSidebar` to match reference pixel-for-pixel where possible (header, selected pill, LIBRARY section rows, storage bar, footer icons).
- Make "Library Desk" selection visually dominant.

**Phase 2 – Search + Filters Header**
- Rebuild the header row to exactly replicate the reference layout:
  - Label
  - Search pill
  - Filter chip toolbar (All + Favorites + Untagged + Has Tags + 4 dropdown pills)
  - Right-side count + sort + view mode
- Wire the dropdown pills to real filters where possible (Date, Duration, Resolution). "More Filters" can open existing advanced UI or a placeholder.

**Phase 3 – Grid Card Redesign**
- Update `VideoGridCell` (and any shared styling) for:
  - Thumbnail framing and corner treatment
  - Duration badge (position, size, background, font)
  - Star / favorite indicator placement
  - Title + meta typography and layout under the image
  - Selection treatment (ring weight, surface change)
- Verify spacing and 4-column behavior at reference widths.

**Phase 4 – Viewer + Inspector Polish**
- Player area: frame, control bar treatment (may need custom or styled `AVPlayer` overlay).
- Metadata: title + specs line (exact formatting, separators, icons).
- Inspector:
  - Rating stars visual weight + Clear button
  - Tag chips (exact shape, color, remove affordance, add button)
  - Notes text area + counter
- Add the "INSPECTOR: RATING / TAGS / NOTES" label.

**Phase 5 – Micro Polish & Responsiveness**
- Overall padding, divider weights, hover states.
- Ensure the layout remains attractive at different window sizes.
- Verify list view (if shown) doesn't regress.
- Performance check on grid (keep cells lightweight).
- Build + rename to VMLibrary + side-by-side review.

**Phase 6 (optional) – Advanced**
- "Save View" button behavior.
- Smarter filter dropdown menus.
- Better drag/resize feel on the main split.
- Keyboard focus styles that match the visual language.

---

## 11. Files Likely to Change

- `Skagway/Views/Sidebar/LibraryDeskSidebar.swift` (major)
- `Skagway/Views/ContentView.swift` (browse header area, zone labels, main layout structure)
- `Skagway/Views/Library/LibraryGridView.swift` + `VideoGridCell` (inside same file)
- `Skagway/Views/Detail/VideoDetailView.swift` (inspector subsections, player framing)
- `Skagway/Design/DesignSystem.swift` (possible new tokens / modifiers)
- Possibly new small components:
  - `FilterPill.swift` or similar for the filter chip row
  - Refined `RatingView` usage or a viewer-specific one
  - `StorageBar.swift`

Also:
- `LibraryViewModel.swift` (may need small additions for new filter affordances)
- Any supporting views for duration, specs, tag chips (reuse where possible)

---

## 12. Success Criteria (How We Know We're Done)

- Side-by-side with the reference image, an average viewer should say "that's the same layout".
- Key call-outs:
  - Left sidebar selection treatment and LIBRARY section look right.
  - Filter chip row has the exact sequence and styling of pills + dropdowns.
  - Grid cards have correct duration badge, star, typography, and selection.
  - Viewer metadata + inspector subsections match the visual hierarchy and component treatment.
- No major visual elements from the reference are missing or grossly different.
- The app still feels fast and the Cinematic Blue language is preserved.

---

## Feedback Addressed (2026-06-28)

User notes after initial prototype:
1. The sidebar should show collections and allow new collection to be added.  
   → Implemented: "COLLECTIONS" section in `LibraryDeskSidebar` with live list (counts), tap-to-filter, context menu (edit/delete), and "New Collection" that presents `CollectionEditorView`.

2. The library section needs to show the smart libraries from the main Skagway branch (corrupted, duplicates, etc).  
   → Implemented: Full LIBRARY list now includes All Videos + Recently Added/Played + Top Rated + Duplicates + Corrupt + Missing + Imports (respecting show* toggles and using the real `SidebarFilter` cases).

3. There appears to be no way to actually filter on tags, rating, duration.  
   → Implemented:
   - **Tags**: Primary nav "Tags" reveals a working multi-select tag list in the sidebar (with ALL/ANY). Header "Has Tags" seeds selection. Grid filters via existing `selectedTagIds` + `tagFilterMode`.
   - **Rating**: Primary nav "Ratings" reveals star rows (5→1). Taps toggle into `selectedRatingStars`. Grid filters live.
   - **Duration**: Header now has functional "Any Duration" / "< 1 min" / "1–5 min" / "5–30 min" / "> 30 min". Wired new `minDurationSeconds` / `maxDurationSeconds` into `LibraryViewModel` snapshot + both sync/async filter paths.

These changes are in build 415 (VMLibrary.app).

## 13. Process Recommendations

1. We work one phase (or one major component) at a time.
2. After each meaningful change we build → rename to VMLibrary → you review side-by-side with the reference.
3. You give specific textual feedback ("the duration badge is too light", "move the star to bottom-left of the image", "make the selected nav pill stronger", etc.).
4. We keep the plan updated (or mark sections complete) as we go.

---

**Next step after you review this plan:**  
Tell me which phase or specific area to start with (or any adjustments to the plan itself). Then we execute methodically with builds after each significant chunk.

This document lives at `LibraryDesk_Implementation_Plan.md` in the project root for easy reference.
