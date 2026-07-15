# Packaging assets

## DMG background

`dmg-background.png` is the Finder window backdrop for `scripts/package_dmg.sh` (via `create-dmg`).

**Hard requirement:** the PNG must be **exactly** the same pixel size as `--window-size` in the script (currently **640×480**).

Finder maps background pixels 1:1 to the window. A larger “Retina 2×” image usually does **not** scale down — you only see the top-left corner (often empty sky).

### Regenerating art

Image generators may not offer a 3:2 / 640×480 preset (e.g. Cursor’s tool allows `1:1`, `4:3`, `3:4`, `16:9`, `9:16`). Generate at **4:3**, then resize:

```bash
sips -z 480 640 path/to/source.png --out packaging/dmg-background.png
```

Bake the “Drag Skagway to Applications” arrow/text into the image; leave clear lower-left / lower-right zones for the app and Applications icons.
