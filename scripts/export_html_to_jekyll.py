#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["beautifulsoup4", "markdownify>=1.2.0", "pyyaml"]
# ///
"""
export_html_to_jekyll.py - turn the post pages in a Tumblr export zip into hidden Jekyll posts.

The Tumblr API only returns what is live on the blog. A blog export also holds posts
that are no longer public (drafts, private, deleted ...). This script reads the
export's html/<post id>.html pages and writes one Jekyll post for each post that is
NOT already on the site, with `published: false` so Jekyll leaves it out of the build.
Switch "Published" on in the CMS (or edit the front matter) to show one.

What it keeps: text, links, tags and the post date. What it can't keep: pictures.
The export's images exist only as files on your computer, so each post records their
file names in `export_media` and shows a plain-text placeholder line like
`[image: 826842209897889792.jpg - not uploaded yet]` where a picture was.

Dates: the export shows times in the blog's local time, not UTC. This script reads them
as America/New_York (checked against two posts that are also on the live blog: the export
said 12:31pm and 5:04pm where the Tumblr API said 16:31 and 21:04 GMT, a 4-hour gap).
Change TIMEZONE below if your blog uses another timezone.

Behaviour:
- Skips posts already on the site (any file in <site>/_posts whose `id` matches).
- Skips posts already written by an earlier run (resumable); --force rewrites them.
- One failing page never stops the run.
- Writes results-log-{timestamp}.txt in the current folder on every run, and prints its path.

Usage:
    uv run scripts/export_html_to_jekyll.py --zip posts.zip --dry-run
    uv run scripts/export_html_to_jekyll.py --zip posts.zip
    uv run scripts/export_html_to_jekyll.py --zip posts.zip --site glosse-me --force
"""

import argparse
import html as htmllib
import re
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml
from bs4 import BeautifulSoup
from markdownify import markdownify

TIMEZONE = ZoneInfo("America/New_York")
UTC = ZoneInfo("UTC")
TS_RE = re.compile(r"([A-Za-z]+)\s+(\d+)\w*,\s+(\d{4})\s+(\d+):(\d+)\s*(am|pm)", re.I)
MEDIA_RE = re.compile(r"\.\./\.\./media/([^\"'\s>]+)")


class SkipPost(Exception):
    """A post left out on purpose (not an error)."""


def parse_date(text: str) -> datetime:
    m = TS_RE.search(text or "")
    if not m:
        raise ValueError(f"no date found in {text!r}")
    month, day, year, hour, minute, ap = m.groups()
    hour = int(hour) % 12 + (12 if ap.lower() == "pm" else 0)
    local = datetime.strptime(f"{month[:3].title()} {int(day)} {year}", "%b %d %Y").replace(
        hour=hour, minute=int(minute), tzinfo=TIMEZONE
    )
    return local.astimezone(UTC)


def convert(page: str, post_id: str) -> dict:
    soup = BeautifulSoup(page, "html.parser")
    ts = soup.find(id="timestamp")
    when = parse_date(ts.get_text(" ", strip=True) if ts else "")
    tags = [htmllib.unescape(s.get_text(strip=True)) for s in soup.select("span.tag")]
    tags = [t for t in tags if t]

    body = soup.body or soup
    footer = body.find(id="footer")
    if footer:
        footer.decompose()

    media = []
    for img in body.find_all("img"):
        m = MEDIA_RE.search(img.get("src", ""))
        name = m.group(1) if m else None
        if name and name not in media:
            media.append(name)
        img.replace_with(soup.new_string(f"\n\n[image: {name or img.get('src', '?')} - not uploaded yet]\n\n"))

    title = ""
    for h in body.find_all("h1"):
        txt = h.get_text(" ", strip=True)
        if txt:
            title = txt
            break

    md = markdownify(str(body), heading_style="ATX", bullets="-")
    md = re.sub(r"[ \t]+\n", "\n", md)
    md = re.sub(r"\n{3,}", "\n\n", md).strip()

    return {
        "id": post_id, "when": when, "tags": tags, "media": media, "title": title, "body": md,
    }


def render(p: dict) -> str:
    fm = {
        "layout": "post",
        "id": p["id"],
        "title": p["title"],
        "date": p["when"].strftime("%Y-%m-%d %H:%M:%S +0000"),
        "published": False,
        "tags": p["tags"],
        "type": "photo" if p["media"] else "text",
        "permalink": f"/post/{p['id']}/",
        "source": "tumblr export (no longer on the live blog)",
        "export_media": p["media"],
    }
    front = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True, default_flow_style=False, width=120)
    return f"---\n{front}---\n\n{p['body']}\n"


def existing_ids(posts_dir: Path) -> dict[str, str]:
    """id -> 'hidden' (written by this script) or 'site' (already a post), for every post file."""
    found = {}
    for f in posts_dir.glob("*.md"):
        text = f.read_text(encoding="utf-8")
        m = re.match(r"---\s*\n(.*?)\n---", text, re.S)
        if not m:
            continue
        try:
            data = yaml.safe_load(m.group(1)) or {}
        except yaml.YAMLError:
            continue
        pid = str(data.get("id", ""))
        if pid:
            found[pid] = "hidden" if data.get("published") is False else "site"
    return found


def items(rows):
    return "  (none)" if not rows else "\n".join(f"  {a}\n      {b}" for a, b in rows)


def write_log(path, started, finished, args, out, total, b):
    lines = [
        "export_html_to_jekyll results log",
        "=" * 60,
        f"Run started : {started.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Run finished: {finished.strftime('%Y-%m-%d %H:%M:%S')}  (duration {str(finished - started).split('.')[0]})",
        f"Input       : {args.zip}" + (" (dry run)" if args.dry_run else ""),
        f"Output      : {out}",
        "",
        "SUMMARY",
        "-" * 60,
        f"  Total post pages        : {total}",
        f"  Done this run           : {len(b['written'])}",
        f"  Already done (skipped)  : {len(b['already'])}",
        f"  Skipped on purpose      : {len(b['onsite'])}",
        f"  Errors                  : {len(b['errors'])}",
        "",
        f"SUCCESSFUL: WRITTEN ({len(b['written'])})", items(b["written"]), "",
        f"SUCCESSFUL: SKIPPED, ALREADY IN OUTPUT ({len(b['already'])})", items(b["already"]), "",
        f"SKIPPED ON PURPOSE: ALREADY A POST ON THE SITE ({len(b['onsite'])})", items(b["onsite"]), "",
        f"ERRORS ({len(b['errors'])})", items(b["errors"]), "",
        f"WARNINGS ({len(b['warnings'])})", items(b["warnings"]), "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description="Turn Tumblr-export post pages into hidden Jekyll posts.")
    ap.add_argument("--zip", required=True, help="the posts.zip from the Tumblr export")
    ap.add_argument("--site", default="glosse-me", help="Jekyll site folder (default glosse-me)")
    ap.add_argument("--dry-run", action="store_true", help="write nothing, just report")
    ap.add_argument("--force", action="store_true", help="rewrite hidden posts from earlier runs")
    args = ap.parse_args()

    started = datetime.now()
    out = Path(args.site).resolve() / "_posts"
    log_path = Path(f"results-log-{started.strftime('%Y-%m-%d_%H%M%S')}.txt")
    b = {"written": [], "already": [], "onsite": [], "errors": [], "warnings": []}
    total = 0
    try:
        if not out.is_dir():
            raise SystemExit(f"{out} not found. Run from the repo root or pass --site.")
        known = existing_ids(out)
        with zipfile.ZipFile(args.zip) as z:
            pages = sorted(n for n in z.namelist() if re.fullmatch(r"html/\d+\.html", n))
            for name in pages:
                total += 1
                pid = Path(name).stem
                try:
                    state = known.get(pid)
                    if state == "site":
                        b["onsite"].append((name, "published post with this id already exists"))
                        continue
                    if state == "hidden" and not args.force:
                        b["already"].append((name, "hidden post already written"))
                        continue
                    p = convert(z.read(name).decode("utf-8", "replace"), pid)
                    if not p["body"] and not p["media"]:
                        b["warnings"].append((name, "page has no text and no pictures"))
                    dest = out / f"{p['when'].strftime('%Y-%m-%d')}-{pid}.md"
                    if state == "hidden":  # --force: remove the old file (its date part may differ)
                        for old in out.glob(f"*-{pid}.md"):
                            if not args.dry_run:
                                old.unlink()
                    if not args.dry_run:
                        dest.write_text(render(p), encoding="utf-8")
                    detail = f"{dest.name}: {len(p['tags'])} tags, {len(p['media'])} picture(s), {len(p['body'])} chars"
                    b["written"].append((name, detail))
                except Exception as e:  # noqa: BLE001 - one bad page never stops the run
                    b["errors"].append((name, f"{type(e).__name__}: {e}"))
    except SystemExit as e:
        b["errors"].append(("startup", str(e)))
    except Exception as e:  # noqa: BLE001
        b["errors"].append(("unexpected", f"{type(e).__name__}: {e}"))
    finally:
        write_log(log_path, started, datetime.now(), args, out, total, b)
        print(f"Results log: {log_path.resolve()}")
        print(f"Output     : {out}")
        print(f"Written {len(b['written'])}, already {len(b['already'])}, on site {len(b['onsite'])}, errors {len(b['errors'])}")
    sys.exit(1 if b["errors"] else 0)


if __name__ == "__main__":
    main()
