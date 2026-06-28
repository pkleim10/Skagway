# VideoMaster Roadmap

This document captures the high-level vision and major phases for VideoMaster. Detailed feature and improvement ideas are captured here (under the relevant Phase) or in `AI-IMPROVEMENTS.md`. (Older separate files `IMPROVEMENTS.md` and `DEVELOPMENT_SUMMARY.md` have been retired into this roadmap.)

## Vision

A fast, native macOS app that lets people **find, organize, and enjoy** their personal video libraries — without forcing them to move files into a proprietary container.

Key qualities:
- Excellent performance even with thousands of videos
- Deep macOS integration and keyboard-driven workflow
- Respect for the user's existing folder structure
- High-quality inline playback + useful organization tools (ratings, tags, collections, custom metadata)

## Current State (as of v0.13.0)

**Core experience is solid**:
- Grid + List browsing with fast filtering and sorting
- Star ratings, tags, custom metadata
- Rule-based collections
- Multiple playback modes (detail pane, overlay, full screen)
- Filmstrip navigation
- In-app re-encoding (MP4)
- Subtitles support (sidecar .srt)
- Resume playback positions
- Strong keyboard support and navigation commands
- Recently Converted filter + conversion workflow

**Known architectural strengths**:
- Careful performance work around SwiftUI diffing and large datasets
- Clean separation via ViewModel + Repository pattern
- Layout persistence that handles browsing vs. playback modes

## Major Themes / Phases (High Level)

### Phase 0 — Foundations (largely complete)
- Core browsing, metadata, playback, scanning
- Performance baseline
- Build / release discipline

### Phase 1 — Polish & Reliability (current focus area)
- Eliminate remaining UX friction (scroll position, selection after rename, filter clearing behavior, etc.)
- Make playback modes feel consistent and predictable
- Improve discoverability (sort indicator in grid, better navigation UI)
- Strengthen subtitle and conversion workflows
- Better handling of edge cases (missing files, corrupt media, large libraries)

### Phase 2 — Power User & Organization Features
- Smarter organization tools (better collections, notes, auto-tagging ideas)
- Advanced search (beyond filename FTS5)
- Batch operations and multi-select power features
- Import / library management improvements (auto-import from data sources?)

### Phase 3 — AI Augmentation (exploratory)
- See `AI-IMPROVEMENTS.md`
- Potential areas: semantic search, smart tagging, content-aware suggestions, duplicate detection

### Phase 4 — Distribution & Longevity
- Proper app sandboxing (if/when feasible)
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

*Last significant update: around the v0.13 timeframe.*