# Design: Layered Filtering — Quick Filters + Advanced Rule Builder (one engine)

**Type:** Design document for review (implementation planned separately, in phases).

---

## 1. Context

VideoMaster just shipped custom-field filtering (v0.32.0), but the live **Filters Drawer** still has three gaps that read as unfinished for a pro-level product:

- **Missing built-in fields.** The drawer can filter on rating, duration, tags, and custom fields — but not file size, resolution, dates, play count, codec, folder, extension, etc.
- **AND-only.** Every filter category is AND'd together; there's no way to express "marvel OR dc".
- **No complexity gradient.** It's one flat surface — no room to grow into power-user territory without cluttering the common case.

**The key discovery (from code exploration):** VideoMaster *already contains a complete boolean rule engine* — the **Collections** system. `RuleAttribute` (`Models/Collection.swift:86`) covers 15 built-in fields (name, extension, path, parentFolder, volume, fileSize, duration, height, width, codec, dateImported, dateCreated, playCount, rating, tag); `RuleComparison` (`:168`) has 10 operators; `CollectionRuleGroup` + `VideoCollection` give **two-level AND/OR grouping**; and `CollectionRepository.GroupedMatcher`/`compileRule` compile rules into fast per-video predicate closures. This engine is a **strict superset** of the drawer's field coverage.

So today there are **two parallel, non-shared filter systems**: the live drawer (simple, AND-only, limited fields + custom fields) and the Collections engine (rich, AND/OR, all built-in fields — but *saved* smart folders only, with a weak plain-text editor and no custom-field support).

**The opportunity:** unify them. One filter language backs the quick drawer, an advanced rule builder, *and* Collections. The "advanced layer" the user wants isn't a new engine — it's the Collections engine, applied as an ad-hoc live filter, extended with custom fields + type-aware editors + a `between`/range operator, and surfaced progressively.

**Intended outcome:** a filtering experience that stays as simple as today for regular users, scales to full boolean power for pros, closes the missing-field gaps, and lets a user **convert any filter into a saved Collection**.

---

## 2. Core thesis — one language, three tiers of exposure

> **There is exactly one filter model.** Quick controls are just canonical, pre-configured conditions in that model. The advanced builder is the full editor of the same model. A Collection is that model, named and saved.

Complexity is **opt-in and layered**:

| Tier | Who | What they see | Combines as |
|---|---|---|---|
| **0 — Pinned quick filters** | everyone | Smart Libraries, Collections, Rating, Duration, Tags — always visible, one tap, no operators | AND |
| **1 — "Add filter" rows** | anyone who needs more | a menu of *every* remaining field (built-in + custom); each adds a removable row with a **smart default control** for its type (quality chips, size range, date presets, Unplayed/Played toggle, contains-box…) — still no operator dropdowns | AND |
| **2 — Advanced rule builder** | power users, on demand | an inline expander: field · operator · value rows, **ALL/ANY**, and **condition groups (OR)** — the same mental model as the Collections editor | ALL/ANY + groups |

Each tier **builds on the one below**: Tier 1 lives in the same drawer as Tier 0 and adds to the same AND set; Tier 2 exposes that same set as an editable boolean tree. Nothing is a separate system.

Tier 1 reuses a pattern the app *already ships*: the custom-fields card's "Add Filter menu → removable typed row" (`CuratedWallFiltersDrawer.swift:618`). We simply extend that menu to include built-in fields.

---

## 3. The unified model

Generalize the Collections model so it can back both live filtering and saved Collections, and cover custom fields.

```
FilterField                     // what to test
  ├─ .builtin(RuleAttribute)    // the existing 15 attributes, unchanged
  └─ .custom(UUID)              // a CustomMetadataFieldDefinition

FieldKind  (drives valid operators + which value editor to show)
  string · number · fileSize · duration · rating · resolution · date · tag · playCount · bool

FilterOperator                  // RuleComparison + additions
  = equals, notEquals, contains, startsWith, endsWith, matches,
    lessThan, greaterThan, atMost, atLeast,
    between,                     // NEW — ranges in one condition (today needs 2 rules)
    before, after, on, inRange, // date-friendly aliases
    isEmpty/isNotEmpty          // (custom fields)

FilterValue                     // typed, replacing today's value:String
  = text(String) | number(Double) | numberRange(Double?,Double?)
  | date(Date) | dateRange(Date?,Date?) | relativeDate(RelativePreset)
  | rating(Int) | resolutionBucket(Bucket) | tag(Int64) | bool(Bool)

FilterCondition  = FilterField + FilterOperator + FilterValue
FilterNode       = .condition(FilterCondition) | .group(FilterGroup)
FilterGroup      = matchMode(.all/.any) + [FilterNode]     // nesting allowed in model; UI caps at 2 levels (matches validated Collections design)
```

- The **live filter** becomes a single **working `FilterGroup`** on `LibraryViewModel`. Tier 0/1 controls read/write specific conditions inside it; Tier 2 edits the whole tree.
- A **Collection** becomes `{ name, FilterGroup }` — the same structure, persisted.
- **One matcher** generalizes `GroupedMatcher`/`compileRule` to compile a `FilterGroup` → `(Video, [Tag], customMetadata) -> Bool`, backing live filter + Collections + counts.
- The existing 15 `RuleAttribute` cases and 10 `RuleComparison` cases are **preserved** as the built-in subset — no capability is lost; we add custom fields, richer values, and `between`.

**Reuses:** `RuleAttribute`/`RuleComparison`/`StringMatcher`/`compareNumeric`/`compareDay` (`CollectionRepository.swift`), `CustomFieldValueParser` (`LibraryViewModel.swift:1640`, already shared by sort+filter), `Video.resolutionLabel`/`formattedFileSize`/`formattedDuration` for value editors and pills.

---

## 4. Field × control matrix (type-aware editors)

The single biggest UX upgrade over today's Collections editor (which is *always a plain text box*) is a **control that fits the field's type** — in both the quick rows (Tier 1) and the advanced builder (Tier 2).

| Field kind | Fields | Quick control (Tier 1) | Advanced ops (Tier 2) | Pill example |
|---|---|---|---|---|
| rating | Rating | star picker (reuse `RatingView`) | =, ≥, ≤, between | `★★★★+` |
| duration | Duration | Min–Max minutes | ≥, ≤, between | `10–45 min` |
| fileSize | File Size | Min–Max + unit (MB/GB) | ≥, ≤, between | `>2 GB` |
| resolution | Quality | bucket chips SD·720p·1080p·4K… (reuse `resolutionLabel`) | is / at least / at most | `≥1080p` |
| date | Date Added, Date Created | preset menu (Today, This week, Month, Year, Last N days) + custom range | before, after, on, between | `Added: this month` |
| playCount | Plays | **Unplayed / Played** toggle + optional threshold | =, ≥, ≤, between | `Unplayed` |
| tag | Tag | tag menu (reuse tag chips) | includes / excludes / any / all | `#marvel` |
| string | Name, Codec, Extension, Folder, Path, Volume, custom text | contains-box | contains, is, starts/ends with, regex | `Codec: hevc` |
| number | Width, Height, custom number | Min–Max | =, ≥, ≤, between | `Height ≥ 2160` |

"Quality" and "Unplayed/Played" are new *derived* quick filters over existing raw fields (`resolutionLabel` buckets; `playCount == 0` vs `> 0`) — high-value for a video library and cheap to add.

---

## 5. Wireframes

### Tier 0 + Tier 1 — the drawer (regular user)

```
┌─ FILTERS ─────────────────────────────────────────────────── Clear all ─┐
│                                                                          │
│  SMART LIBRARIES     RATING            TAGS  [Any|All]     + Add filter ▾ │
│  ● All Videos        ★★★★☆             ✓ #vacation         ┌───────────┐  │
│    Recently Added    DURATION            #family           │ Quality   │  │
│    Top Rated         [10]–[45] min       #4k               │ File size │  │
│    Duplicates                                              │ Date added│  │
│                                                            │ Plays     │  │
│  COLLECTIONS         ─ added rows (all AND) ─────────────  │ Codec     │  │
│    Marvel Movies      Quality  [SD][720p][●1080p][●4K]  ✕  │ Folder…   │  │
│    Shorts             Plays    (●)Unplayed ( )Played    ✕  │ Director* │  │  ← * = custom field
│                       Date added   [This month ▾]       ✕  └───────────┘  │
│                                                                          │
│  ▸ Advanced rules                                                        │
└──────────────────────────────────────────────────────────────────────────┘
```

Regular users never see an operator or an AND/OR toggle. "Add filter" is the one discovery affordance, and it's a pattern already shipping for custom fields.

### Tier 2 — Advanced rules expanded (power user)

```
┌─ FILTERS ─────────────────────────────────────────────────── Clear all ─┐
│  Quick filters ▸ (2 active)                        Matching: 342 videos  │
│                                                                          │
│  ▾ Advanced rules              Match [ ALL ▾ ] of the following:         │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │  Quality        is at least   [ 1080p ▾ ]                  – +   │     │
│  │  Date added     is after      [ 2024-01-01 📅 ]            – +   │     │
│  │  ┌─ Match [ ANY ▾ ] of: ───────────────────────────────┐  – +   │     │
│  │  │  Tag        includes      [ #marvel ▾ ]        – +   │        │     │
│  │  │  Tag        includes      [ #dc ▾ ]            – +   │        │     │
│  │  └──────────────────────────────────────────────────────┘       │     │
│  └────────────────────────────────────────────────────────────────┘     │
│  + Add condition     + Add group                                         │
│                                                                          │
│  [ Save as Collection… ]                              [ Reset filter ]   │
└──────────────────────────────────────────────────────────────────────────┘
```

Reads: **Quality ≥1080p AND added after 2024-01-01 AND (tag marvel OR tag dc)** — a real power query, in the same ALL/ANY-group vocabulary the Collections editor already uses (and the user already validated as "pro level"). The drawer auto-resizes / can be dragged taller to fit (existing `filtersDrawerHeight` + fit-to-content behavior).

### Graceful escalation — Basic honestly reflects Advanced

The working filter is a top-level ALL group by default; quick controls edit flat conditions in it. The moment Advanced introduces **OR or a group** (only possible in Tier 2), the structure can't be shown as simple AND chips — so Tier 0/1 collapses to an honest read-only summary rather than lying:

```
┌─ FILTERS ─────────────────────────── Clear all ─┐
│  ⚑ Advanced rules active                         │
│  Quality ≥1080p · Added after 2024 · (marvel OR  │
│  dc)                              [ Edit rules ]  │
│  ▾ Advanced rules …                              │
└───────────────────────────────────────────────────┘
```

This mirrors how Airtable/Notion degrade — the quick surface never misrepresents what's actually matching.

### Convert filter → Collection (the requested bridge)

```
   [ Save as Collection… ]  ──►  ┌─ Save as Collection ─────────────┐
                                 │ Name: [ 4K Marvel/DC 2024      ]  │
                                 │ 3 conditions · 1 group            │
                                 │           [ Cancel ]   [ Save ]   │
                                 └───────────────────────────────────┘
```

Trivial once unified: the working `FilterGroup` *is* a Collection's body. The reverse — **"Edit Collection as filter"** (load a saved Collection's group into the working filter) — falls out for free and makes Collections feel live and editable.

---

## 6. Why this appeals to both audiences

**Regular users** get *today's* experience or simpler: always-visible common filters, one "Add filter" menu, smart default controls (chips/toggles/presets — no operators), readable pills. They can ignore Advanced forever.

**Power users** get: every field, every operator (incl. regex + `between`), ALL/ANY, OR groups, live result counts, and a one-click path to persist any query as a Collection — all in one coherent language, not a second tool.

**The product** gets: one engine instead of two diverging ones; Collections' editor upgraded to type-aware controls for free; and a genuine "filters ⇄ smart collections" story that reads as a finished, professional system.

---

## 7. Phased implementation path (de-risked; each phase ships value)

- **Phase 1 — Quick-filter completeness (no engine change).** Extend the existing custom-fields "Add filter" card pattern to cover the missing built-in fields (Quality buckets, File size, Date added/created, Plays incl. Unplayed, Codec, Extension, Folder, …) as simple AND rows in the *current* live-filter state. Closes the missing-field gap immediately, reuses shipped code, zero risk to Collections. **This is the fast win.**
- **Phase 2 — Unify the model + matcher.** Introduce `FilterField`/`FilterCondition`/`FilterGroup` + generalized matcher; re-point the live filter to a working `FilterGroup`; migrate Collections onto the same model (additive schema/encoding migration; existing 15 attributes + 10 operators preserved), upgrading its editor to the type-aware value controls. Behavior-preserving internal refactor. **Biggest lift.**
- **Phase 3 — Advanced tier.** Inline "Advanced rules" expander over the working `FilterGroup`: operators, ALL/ANY, one level of OR groups, `between`. Graceful escalation from Basic. **Adds OR.**
- **Phase 4 — Bridges.** "Save as Collection…" and "Edit Collection as filter." Small once unified.

Value lands at Phase 1 (missing fields) *before* the risky unification; OR logic arrives at Phase 3.

---

## 8. Open decisions (for the implementation planning stage)

- **Persistence of the live working filter across relaunch?** Today all live filters reset each session. A saved boolean query is more valuable to keep — but that's a behavior change. Likely: keep session-only to match siblings, and lean on "Save as Collection" for durability. (Confirm at build time.)
- **Nesting depth.** Model allows arbitrary; UI caps at 2 levels to match the validated Collections design. Revisit only if users ask.
- **`between` for dates vs. two conditions.** Preferred as one condition with a from/to; verify the matcher's day-granularity handling extends cleanly.
- **Migration encoding** for Collections' `value:String` → typed `FilterValue` (additive; old rows decode into the built-in/text subset).

---

## 9. How we'd validate

This is a design doc, so "verification" = design validation before building:
1. Walk the three wireframes against the top ~10 real queries a user would want (e.g. "unplayed 4K movies", "shorts added this week", "marvel OR dc, ≥4 stars") and confirm each is expressible and readable.
2. Confirm every current Collections rule remains expressible post-unification (no regression of the validated feature).
3. Confirm Tier 0/1 never exposes operators/AND-OR, and that graceful escalation never misrepresents the active filter.
4. Once a phase is built: the standard loop — `bash scripts/build_and_install.sh`, drive each tier in the running app, verify results/counts/pills against hand-computed expectations at 12k-video scale.
