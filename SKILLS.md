# SKILLS.md — VideoMaster

This document describes the skills, subagents, and specialized workflows used when developing VideoMaster with AI assistance.

## Philosophy

We use a combination of:
- General-purpose coding
- Project-specific rules (see `.cursor/rules/`)
- Targeted skills and subagents for higher-quality outcomes on complex or repetitive tasks

The goal is to be **deliberate** about when we use specialized agents rather than always using a single general agent.

## Core Project Skills / Workflows

### 1. Build & Deploy Discipline
**Always use** the canonical script after code changes:
```bash
bash scripts/build_and_install.sh
```

After the script succeeds:
- Stage **all** changes with `git add -A` (tracked modifications + untracked files).
- Add high-level summaries of the changes to the `## Unreleased` section of `CHANGELOG.md`.
- Commit the work (including the changelog update).
- This is required for every code change.

This is enforced by the `build-deploy.mdc` rule.

### 2. Release Workflow
Use the documented release process in `.cursor/rules/release-workflow.mdc` (which points to the authoritative "Release Commands" in `.cursor/rules/build-deploy.mdc`) for patch/minor/major releases. This includes:
- Staging everything with `git add -A`
- Committing **all completed work** as part of the release (no completed changes left behind)
- Proper versioning, changelog consolidation, tagging, and announcements

### 3. Performance & Architecture Work
When doing performance work or large refactors:
- Profile mentally first (SwiftUI diffing, main-thread work, layout thrashing).
- Prefer solutions that have already worked in this codebase (`filteredVideosVersion`, versioned IDs, batched queries, O(1) scroll commands, etc.).
- Update relevant performance docs (`GRID-PERFORMANCE.md`).

### 4. Playback Mode Awareness
Any change that touches playback must consider the three modes:
- Detail pane (freezes browser)
- Overlay
- Full screen

Respect `inlinePlaybackReshapesBrowser` and test exit paths (especially grid retiling and column width restoration).

## Recommended Specialized Subagents / Skills

These are examples of when to invoke more focused agents (using Cursor's subagent or skill mechanisms):

| Task Type                    | Suggested Approach                     | Why |
|-----------------------------|----------------------------------------|-----|
| Large refactors / architecture | Use a dedicated architecture or "explore" subagent first | Get a clean map before editing |
| Performance investigations   | Explore + profile-focused subagent    | Avoid premature or wrong optimizations |
| Bug triage on complex flows (playback, scroll, filters) | Bugbot-style review subagent          | Systematic reproduction + root cause |
| Security / entitlements review | Security review subagent             | App has disabled sandboxing |
| Writing or updating rules    | `create-rule` style skill             | Keep rules high-quality and minimal |
| Creating project skills      | `create-skill` style skill            | Build reusable project capabilities |
| Code review before commit    | Review subagent (bugbot or general)   | Catch issues the main agent may have introduced |
| Release preparation          | Follow release-workflow.mdc + build-deploy.mdc + human verification | Versioning and tagging are high-stakes |

## Project-Specific Skills We May Develop

- `videomaster-playback-test` — Guide through testing all three playback modes + enter/exit/switch/scroll/column restore behavior. (Created)
- `videomaster-build-check` — Validate that a change follows build/deploy rules.
- `videomaster-filter-audit` — Analyze current filter state and performance characteristics.
- `videomaster-scroll-debug` — Help debug scroll position and retiling issues.

When we create reusable skills, document them here and place the implementation according to Cursor's skills system (global or project-local).

## How to Invoke Skills & Subagents

- In Cursor, use the appropriate composer mode, agent, or `/` commands when available.
- For complex work, start by asking the main agent to "use the appropriate subagent for X".
- Always surface the subagent's findings or actions back into the main thread.

## When NOT to Use Heavy Specialization

- Trivial bug fixes
- Small UI tweaks
- Purely mechanical refactors

Use judgment. Overusing subagents can add more noise than value.

---

**Related files**:
- `.cursor/rules/` — Always-applied or scoped rules
- `AGENTS.md` — Overall agent behavior contract
- `ROADMAP.md` — Strategic direction

Update this file as we formalize more VideoMaster-specific skills.