# Skagway — Claude / Cursor Instructions

See the following foundation documents for how to work on this project:

- **[AGENTS.md](./AGENTS.md)** — Primary agent contract (read this first)
- **[SKILLS.md](./SKILLS.md)** — Skills and subagent usage
- **[ROADMAP.md](./ROADMAP.md)** — High-level direction

## Quick Reference: Building & Deploying

After **every** code change, run:

```bash
bash scripts/build_and_install.sh
```

This script handles build number bump, `xcodegen`, Release build, install to `/Applications`, and cleanup.

Always announce the resulting version (e.g. `✓ Skagway 0.13.0 (375) [Release]`).

For full release process (patch/minor/major), see `.cursor/rules/release-workflow.mdc` and the Release Commands section of `.cursor/rules/build-deploy.mdc`.
