# Packaging assets

## Setup

```bash
brew install create-dmg
```

## DMG background

- `dmg-background.png` — **exactly 640×480**
- `dmg-background-pristine.png` — art backup

Art includes white “Skagway”, “Applications”, arrow, and “Drag Skagway to Applications”.

## Important

`scripts/package_dmg.sh` uses **create-dmg only**. Do not rewrite `.DS_Store` after
create-dmg runs — that breaks the Finder background (gray window).

Icon positions are the `--icon` / `--app-drop-link` arguments in that script; keep
both on the same `y`.

Finder will still draw its own icon names under the icons (create-dmg cannot hide
them without breaking the background). The white captions in the art are the
intended visual labels.
