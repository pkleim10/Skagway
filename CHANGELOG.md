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