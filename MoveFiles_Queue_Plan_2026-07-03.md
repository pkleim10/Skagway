# Move Files — Queue + Safety Spec

**Date:** 2026-07-03
**Status:** Proposed, not yet implemented.
**Mirrors:** The existing Re-encode Queue (`ConversionJob.swift`, `ConversionQueueView.swift`, header `conversionPill`) — same visual language, same interaction model, for UI consistency and because the codebase already has a working precedent for "long-running background file op with visible progress."

## Problem

`LibraryViewModel.moveVideos(_:to:)` (`LibraryViewModel.swift:2127`) already has `isMoving`/`moveProgress` state, but **nothing renders it** — no view reads either property. A move onto a different volume is a real copy + delete under the hood and can take a while; right now the user gets zero feedback and nothing stops them from deleting, re-encoding, or moving the same file again mid-operation.

There's a second, sharper problem underneath the UX one: **`moveVideos` calls `FileManager.moveItem` directly on the real source file.** For a same-volume move that's an atomic rename (safe, instant). For a cross-volume move, `moveItem` internally copies then deletes the source — if the app is force-quit, crashes, or the destination volume is unplugged mid-copy, there's no safety net like the one the re-encode path already has (temp file → verify → promote → keep backup). This spec fixes both: visibility (queue + freeze) and safety (temp-file-then-promote for the copy itself).

## Design

### 1. Same-volume vs. cross-volume — treat them differently

Compare `source.url` and `destination` volume identifiers (`URLResourceValues.volumeIdentifier` on both, via `FileManager.default.componentsToDisplay`/`.volumeURL` — cheapest is `try url.resourceValues(forKeys: [.volumeIdentifierKey])`).

- **Same volume:** `FileManager.moveItem` is an atomic rename — effectively instant, no partial-file risk. Run it synchronously, no queue entry, no freeze. (This is most "Move Files…" usage today — reorganizing within one library folder tree.)
- **Cross volume:** real copy + delete, can take real wall-clock time, needs everything below.

### 2. `MoveJob` model (new file: `Skagway/Models/MoveJob.swift`)

Same shape as `ConversionJob`, adapted:

```swift
struct MoveJob: Codable, Identifiable, Equatable {
    enum Status: Codable, Equatable {
        case queued
        case moving(fractionComplete: Double)   // 0...1, driven by Foundation.Progress
        case completed
        case failed(reason: String)
    }

    let id: UUID
    var videoDatabaseId: Int64?
    var sourcePath: String
    var sourceFileName: String
    var destinationFolderPath: String
    var status: Status
    var enqueuedAt: Date
    var completedAt: Date?
    var newPath: String?     // final destination path, set on completion

    var isActive: Bool { … }   // queued or moving — same pattern as ConversionJob.isActive
}
```

`LibraryViewModel` gains `var moveJobs: [MoveJob] = []` alongside `conversionJobs`, replacing `isMoving`/`moveProgress` (delete both — dead state once the queue lands).

### 3. Safe copy, mirroring the re-encode temp-file pattern

Rewrite the cross-volume path of `moveVideos` to:

1. Copy source → `<destinationFolder>/<name>.moving` (a temp name, not the final name) using `FileManager.copyItem`, wrapped in a `Progress(totalUnitCount:)` made current via `.becomeCurrent(withPendingUnitCount:)`/`.resignCurrent()` so `FileManager`'s built-in progress reporting populates it — this drives `MoveJob.status = .moving(fractionComplete:)` via KVO on `progress.fractionCompleted`.
2. On copy success, verify the destination file size matches the source, then atomically rename `<name>.moving` → `<name>` at the destination.
3. Only now delete the source file and call `videoRepo.renameVideo(...)` (existing DB update logic, unchanged) + `thumbnailService.migrateCacheKey(...)` (unchanged).
4. On any failure (copy error, size mismatch, rename failure), delete the stray `.moving` temp if present, leave the source untouched, mark the job `.failed(reason:)`.

**Crash/force-quit safety:** the source is never touched until the destination copy is verified complete — worst case after an interruption is an orphaned `<name>.moving` file at the destination, source fully intact. On next launch, sweep stray `*.moving` files under any of the app's known data-source folders (mirrors the existing "stray temp file swept" logic for interrupted re-encodes, CHANGELOG 0.22.0).

### 4. Queue processing

One mover at a time (matches "Conversions run one at a time" — same reasoning: predictable disk I/O, simpler progress UI, avoids thrashing a spinning disk or saturating a network volume). New jobs enqueue as `.queued` and the queue drains FIFO.

### 5. Header pill + queue view

- `hasMoveActivity: Bool` (any job not dismissed) and `movePill` in `ContentView.swift`, placed next to `conversionPill` (same row, same capsule styling, `arrow.right.doc.on.clipboard` or similar icon instead of the re-encode icon). Reuse `isConversionActive`'s pattern for `isMoveActive` (spinner vs. static icon).
- `moveStatusText: String` on `LibraryViewModel`, same shape as `conversionStatusText` ("Moving 'x.mp4'… 42% (+2 queued)" / "2 queued to move" / "1 move failed" / "3 moved").
- New `MoveQueueView.swift`, a near-verbatim copy of `ConversionQueueView.swift`'s structure (header/list/row/statusIcon/detail/actions), with a simpler action set per status:
  - `.queued` → Move to Top, Abort
  - `.moving` → Abort (interrupts the `Progress`/copy, cleans up the `.moving` temp, source untouched)
  - `.completed` → Dismiss (no backup concept here, so no Restore/Delete Backup — simpler than the conversion queue)
  - `.failed` → Retry, Dismiss

Completed jobs can just be pruned after being shown briefly (or on next app launch) — there's no backup file to manage, so the conversion queue's 30-day-retention reasoning doesn't apply here; keep only what's useful for "did my move finish/fail."

### 6. Per-file "freeze" — disable conflicting actions while a move is in flight

Add a computed set: `activeMoveVideoIds: Set<String>` (video ids/paths with a `.queued` or `.moving` `MoveJob`) on `LibraryViewModel`.

In both context menus (`CuratedWallGrid.swift` and `LibraryListView.swift` — same block shape in each, confirmed identical structure to the Delete/Move Files items found earlier), for a video in `activeMoveVideoIds`:
- Disable **Delete Video…**, **Move Files…** (can't re-target mid-move), **Re-encode to MP4…**, **Remove from Library**, and **Open With** — all either destructive or assume a stable file handle.
- Leave read-only actions alone (rating, tags, notes, thumbnail regen from cache — nothing that touches the file itself). *(Regenerate Thumbnail does touch the file via `AVAsset` read — worth disabling too, since the source may be mid-copy-then-delete.)*
- `.help("Move in progress — file isn't safe to modify yet")` on the disabled items so it's not just a silent grey-out.

Optional (cheap, nice-to-have — flag for a decision): a small spinner badge overlay on the `CuratedWallCard`/list row for videos in `activeMoveVideoIds`, so the "frozen" state is visible on the wall itself, not just discoverable by right-clicking. Recommend doing this — it's the visual half of "freeze," matching the spinner-in-pill pattern already established for re-encode-in-progress rows in the queue view.

### 7. What doesn't change

- `moveVideos`'s public call sites (`CuratedWallGrid.swift:144`, `LibraryListView.swift:242`) stay the same signature (`[Video]`, destination `URL`) — they just enqueue `MoveJob`s instead of running the loop inline.
- DB update (`videoRepo.renameVideo`), thumbnail cache key migration, and selection-id remapping logic in the current `moveVideos` are correct as-is and get reused verbatim in the "promote" step (§3.3).

## Open decision for you

- **Card-level spinner badge (§6, optional):** yes/no? It's the most visible way to communicate "frozen," but it's an extra bit of UI surface on `CuratedWallCard`/`LibraryListView` row rendering. My recommendation is yes, for the reason above — happy to skip it for a smaller first pass if you'd rather ship the queue+freeze mechanics first and add the badge later.

## Verification plan (once built)

Since I can't drive the GUI myself (per your instruction — build/install only, you test): after building, the repro to hand back would be — move a multi-GB file across two different volumes (e.g. internal disk → an external/network volume) via **Move Files…**, confirm the header pill shows live progress, confirm Delete/Move/Re-encode are greyed out on that card until it completes, then force-quit the app mid-copy and relaunch to confirm the source file is untouched and only a stray `.moving` temp got left at the destination (swept automatically on the relaunch).
