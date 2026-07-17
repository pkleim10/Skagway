#!/usr/bin/env python3
"""
Download a ~100-clip Skagway demo library from Pixabay (free stock video).

Categories (25 each by default):
  Landscape, Architecture, Arts & Crafts, Automotive

Setup:
  python3 scripts/download_demo_library.py

  Optional: export PIXABAY_API_KEY='…' to override the embedded key.
  Get a key at https://pixabay.com/api/docs/ (shown when logged in).

Default output: ~/Movies/Skagway-Demo-Library/
Add that folder as a Skagway data source for screenshots / manuals.

Uses the Videos API: GET https://pixabay.com/api/videos/

License: Pixabay Content License — free commercial use. When publishing
marketing that uses these clips, credit Pixabay (and contributors when easy).
See ATTRIBUTION.json. Not public domain.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

API_BASE = "https://pixabay.com/api/videos/"
DEFAULT_OUT = Path.home() / "Movies" / "Skagway-Demo-Library"
# Local convenience default; PIXABAY_API_KEY env wins. Rotate if this file is public.
_DEFAULT_API_KEY = "56719224-b40ebdf3848e417925b353be9"

# Folder name → (search query, optional Pixabay category filter)
CATEGORIES: dict[str, tuple[str, str | None]] = {
    "Landscape": ("landscape nature scenery", "nature"),
    "Architecture": ("architecture building city", "buildings"),
    "Arts & Crafts": ("arts crafts handmade", None),
    "Automotive": ("car driving automotive", "transportation"),
}

# Prefer medium (typically 1280–1920); avoid empty large 4K when possible
QUALITY_ORDER = ("medium", "large", "small", "tiny")


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def api_get(url: str) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "SkagwayDemoLibrary/1.0",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        die(f"Pixabay API HTTP {e.code}: {body[:400]}")
    except urllib.error.URLError as e:
        die(f"network error talking to Pixabay: {e}")


def pick_mp4(hit: dict[str, Any], prefer_max_width: int) -> dict[str, Any] | None:
    """Pick a landscape-ish MP4 near HD from hit['videos']."""
    videos = hit.get("videos") or {}
    candidates: list[dict[str, Any]] = []
    for quality in QUALITY_ORDER:
        info = videos.get(quality) or {}
        url = (info.get("url") or "").strip()
        w = info.get("width") or 0
        h = info.get("height") or 0
        if not url or not w or not h:
            continue
        candidates.append(
            {
                "url": url,
                "width": w,
                "height": h,
                "quality": quality,
                "size": info.get("size") or 0,
            }
        )
    if not candidates:
        return None

    landscape = [c for c in candidates if c["width"] >= c["height"]]
    pool = landscape or candidates

    under = [c for c in pool if c["width"] <= prefer_max_width]
    if under:
        return max(under, key=lambda c: c["width"])
    return min(pool, key=lambda c: c["width"])


def slugify(text: str, max_len: int = 48) -> str:
    s = text.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return (s[:max_len].rstrip("-") or "clip")


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".partial")
    # download=1 nudges CDN toward attachment-style response
    dl_url = url if "download=" in url else (
        url + ("&" if "?" in url else "?") + "download=1"
    )
    req = urllib.request.Request(
        dl_url,
        headers={"User-Agent": "SkagwayDemoLibrary/1.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as resp, open(tmp, "wb") as out:
            while True:
                chunk = resp.read(1024 * 256)
                if not chunk:
                    break
                out.write(chunk)
        tmp.replace(dest)
    except Exception:
        if tmp.exists():
            tmp.unlink(missing_ok=True)
        raise


def search_videos(
    api_key: str,
    query: str,
    *,
    category: str | None,
    per_page: int,
    page: int,
    min_width: int,
) -> list[dict[str, Any]]:
    params: dict[str, Any] = {
        "key": api_key,
        "q": query,
        "video_type": "film",
        "safesearch": "true",
        "order": "popular",
        "per_page": max(3, min(per_page, 200)),
        "page": page,
        "min_width": min_width,
    }
    if category:
        params["category"] = category
    data = api_get(f"{API_BASE}?{urllib.parse.urlencode(params)}")
    return list(data.get("hits") or [])


def collect_category(
    api_key: str,
    query: str,
    *,
    category: str | None,
    need: int,
    min_width: int,
    seen_ids: set[int],
) -> list[dict[str, Any]]:
    collected: list[dict[str, Any]] = []
    page = 1
    empty_streak = 0
    while len(collected) < need and page <= 8:
        batch = search_videos(
            api_key,
            query,
            category=category,
            per_page=min(50, max(need * 2, 20)),
            page=page,
            min_width=min_width,
        )
        if not batch:
            empty_streak += 1
            if empty_streak >= 2:
                break
        for hit in batch:
            vid = hit.get("id")
            if not isinstance(vid, int) or vid in seen_ids:
                continue
            # Videos API has no orientation filter — keep landscape-ish masters
            videos = hit.get("videos") or {}
            probe = videos.get("medium") or videos.get("large") or {}
            w, h = probe.get("width") or 0, probe.get("height") or 0
            if w and h and w < h:
                continue
            collected.append(hit)
            seen_ids.add(vid)
            if len(collected) >= need:
                break
        page += 1
        time.sleep(0.7)  # stay well under 100 req / 60s
    return collected


def contributor_url(user: str, user_id: Any) -> str | None:
    if not user or user_id is None:
        return None
    return f"https://pixabay.com/users/{urllib.parse.quote(str(user))}-{user_id}/"


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"Output folder (default: {DEFAULT_OUT})",
    )
    parser.add_argument(
        "--per-category", type=int, default=25, help="Clips per category (default: 25)"
    )
    parser.add_argument(
        "--max-width",
        type=int,
        default=1920,
        help="Prefer MP4 width at or below this (default: 1920)",
    )
    parser.add_argument(
        "--min-width",
        type=int,
        default=640,
        help="Pixabay min_width search filter (default: 640)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Search and print what would download; do not write files",
    )
    parser.add_argument(
        "--query",
        help="Custom Pixabay search instead of the built-in categories "
        '(e.g. --query "timelapse city clouds")',
    )
    parser.add_argument(
        "--folder",
        help="Subfolder name for --query results (default: derived from the query)",
    )
    parser.add_argument(
        "--count",
        type=int,
        help="Clips to download for --query (default: --per-category)",
    )
    args = parser.parse_args()

    if args.query:
        folder = args.folder or slugify(args.query).replace("-", " ").title()
        categories: dict[str, tuple[str, str | None]] = {folder: (args.query, None)}
        per_category = args.count or args.per_category
    else:
        if args.folder or args.count:
            die("--folder and --count require --query")
        categories = CATEGORIES
        per_category = args.per_category

    api_key = os.environ.get("PIXABAY_API_KEY", "").strip() or _DEFAULT_API_KEY
    if not api_key:
        die(
            "No Pixabay API key.\n"
            "  Sign in at https://pixabay.com/api/docs/ and set PIXABAY_API_KEY, "
            "or put the key in _DEFAULT_API_KEY in this script."
        )

    out: Path = args.out.expanduser().resolve()
    if not args.dry_run:
        out.mkdir(parents=True, exist_ok=True)

    attribution: list[dict[str, Any]] = []
    attr_path = out / "ATTRIBUTION.json"
    if attr_path.exists() and not args.dry_run:
        try:
            attribution = json.loads(attr_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            attribution = []

    existing_ids = {int(item["id"]) for item in attribution if "id" in item}
    global_seen: set[int] = set(existing_ids)

    total_ok = 0
    total_skip = 0
    total_fail = 0

    print(f"Output: {out}")
    print(f"Target: {per_category} clips × {len(categories)} categories\n")

    for folder, (query, category) in categories.items():
        cat_dir = out / folder
        if not args.dry_run:
            cat_dir.mkdir(parents=True, exist_ok=True)

        already = list(cat_dir.glob("*.mp4")) if cat_dir.exists() else []
        need = max(0, per_category - len(already))
        cat_note = f", category={category}" if category else ""
        print(f"=== {folder} (have {len(already)}, need {need}) q={query!r}{cat_note}")

        if need == 0:
            print("  already complete\n")
            continue

        hits = collect_category(
            api_key,
            query,
            category=category,
            need=need + 5,
            min_width=args.min_width,
            seen_ids=global_seen,
        )
        print(f"  found {len(hits)} candidates")

        saved = 0
        for hit in hits:
            if saved >= need:
                break
            vid = hit["id"]
            file_info = pick_mp4(hit, args.max_width)
            if not file_info:
                print(f"  skip {vid}: no suitable mp4")
                total_skip += 1
                continue

            tags = hit.get("tags") or f"video-{vid}"
            slug = slugify(str(tags).split(",")[0].strip() or f"video-{vid}")
            filename = f"{vid}-{slug}.mp4"
            dest = cat_dir / filename

            if dest.exists():
                print(f"  exists {filename}")
                saved += 1
                total_skip += 1
                continue

            w, h = file_info["width"], file_info["height"]
            user = hit.get("user") or "Unknown"
            print(f"  download {filename} ({w}x{h} {file_info['quality']}) by {user}")

            if args.dry_run:
                saved += 1
                total_ok += 1
                continue

            try:
                download_file(file_info["url"], dest)
            except Exception as e:
                print(f"    FAILED: {e}")
                total_fail += 1
                continue

            attribution.append(
                {
                    "id": vid,
                    "category": folder,
                    "file": f"{folder}/{filename}",
                    "pixabay_url": hit.get("pageURL"),
                    "contributor": user,
                    "contributor_url": contributor_url(user, hit.get("user_id")),
                    "duration_sec": hit.get("duration"),
                    "width": w,
                    "height": h,
                    "quality": file_info["quality"],
                    "license": "https://pixabay.com/service/license-summary/",
                }
            )
            saved += 1
            total_ok += 1
            time.sleep(0.25)

        print(f"  → saved {saved} new clips for {folder}\n")

    if not args.dry_run:
        attr_path.write_text(json.dumps(attribution, indent=2) + "\n", encoding="utf-8")
        readme = out / "README.txt"
        readme.write_text(
            "Skagway demo library (Pixabay stock video)\n"
            "==========================================\n\n"
            "Add this folder as a Skagway data source for screenshots, manuals, and demos.\n"
            "Do not use personal / private libraries for public marketing assets.\n\n"
            "Source: https://pixabay.com/\n"
            "License: https://pixabay.com/service/license-summary/\n"
            "Credit Pixabay (and contributors when easy) on public marketing pages.\n"
            "See ATTRIBUTION.json for per-clip credits.\n\n"
            "Regenerate with: python3 scripts/download_demo_library.py\n",
            encoding="utf-8",
        )

    print(f"Done. downloaded={total_ok} skipped={total_skip} failed={total_fail}")
    if not args.dry_run:
        print(f"Library ready at: {out}")
        print("In Skagway: add that folder as a data source, then browse / screenshot.")


if __name__ == "__main__":
    main()
