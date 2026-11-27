# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Turn the 2006-2009 podcast-feed broadcasts into day pages.

selkouutiset-scrape files each radio broadcast it recovered from Yle's old
podcast feed (April 2006 - February 2009) as podcast-feed/YYYY-MM-DD.xml: the
feed's <item>, verbatim. Its <description> is the broadcast's full text. There
is no Yle HTML page for these days, so process.sh (which works from the HTML
captures) never sees them; this tool writes their pages instead:

  YYYY/MM/DD/index.fi.md   "# Torstai 27.4.2006 (radio)" and the text
  YYYY/MM/DD/edition.json  {"edition": "2006-04-27", "source": "<snapshot>"}

The programme went out Sunday to Thursday. A Friday or Saturday straight after
a broadcast gets a repeat page (the archive's usual rule: a day holds the
newest edition published on or before it), so it is listed as a repeat rather
than as lost. Any other day without a broadcast gets no page; the site lists
it as lost media.

Finnish only: these days are older than process.sh's TRANSLATE_FROM, and this
tool writes no translation request, so nothing here is ever sent to the
translation API.

  uv run tools/podcast_feed_pages.py selkouutiset-scrape/podcast-feed .

Idempotent: a file is only rewritten when its content changes, and existing
days are left alone unless this tool wrote them (edition.json has "source").
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
from pathlib import Path

WEEKDAYS_FI = ["Maanantai", "Tiistai", "Keskiviikko", "Torstai", "Perjantai", "Lauantai", "Sunnuntai"]
FRIDAY, SATURDAY = 4, 5
# A repeat page is written only for a Friday/Saturday at most this many days
# after a broadcast (Thursday -> Friday, Saturday).
MAX_REPEAT_GAP = 2

SOURCE_RE = re.compile(r"^<!-- (\S+) -->")
SEPARATOR_RE = re.compile(r"^\s*[-_=]{5,}\s*$")
# Line starts that Markdown would read as a heading, list, quote or rule.
MD_LEADER_RE = re.compile(r"^(\s*)([#>+*-]|\d+[.)])(\s)")


def description(raw: str) -> str:
    m = re.search(r"<description>(.*?)</description>", raw, re.S)
    if not m:
        return ""
    text = m[1]
    cdata = re.fullmatch(r"\s*<!\[CDATA\[(.*)\]\]>\s*", text, re.S)
    text = cdata[1] if cdata else html.unescape(text)
    # Some items carry light HTML inside the (escaped) description.
    text = re.sub(r"(?i)<br\s*/?>|</p>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text).replace("\r", "")


def to_markdown(day: dt.date, text: str) -> str:
    """Heading, then one paragraph per line; story separators become rules."""
    blocks: list[str] = []
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        if SEPARATOR_RE.match(line):
            if blocks and blocks[-1] != "* * *":
                blocks.append("* * *")
            continue
        blocks.append(MD_LEADER_RE.sub(lambda m: f"{m[1]}\\{m[2]}{m[3]}", line))
    while blocks and blocks[-1] == "* * *":
        blocks.pop()
    heading = f"# {WEEKDAYS_FI[day.weekday()]} {day.day}.{day.month}.{day.year} (radio)"
    return "\n\n".join([heading, *blocks]) + "\n"


def write_if_changed(path: Path, content: str) -> bool:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


def ours(day_dir: Path) -> bool:
    """True if the day is free, or holds a page this tool wrote."""
    ed = day_dir / "edition.json"
    if not (day_dir / "index.fi.md").exists():
        return True
    try:
        return "source" in json.loads(ed.read_text())
    except (OSError, ValueError):
        return False


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("feed_dir", type=Path, help="selkouutiset-scrape/podcast-feed")
    p.add_argument("root", type=Path, help="the cleaned archive root")
    args = p.parse_args()

    editions: dict[dt.date, tuple[str, str]] = {}  # day -> (markdown, source)
    for f in sorted(args.feed_dir.glob("[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].xml")):
        raw = f.read_text(encoding="utf-8")
        src = SOURCE_RE.match(raw)
        if not src:
            sys.exit(f"{f}: no source comment on the first line")
        day = dt.date.fromisoformat(f.stem)
        editions[day] = (to_markdown(day, description(raw)), src[1])
    if not editions:
        sys.exit(f"no broadcasts under {args.feed_dir}")

    pages: dict[dt.date, tuple[str, dict]] = {}
    for day, (md, src) in editions.items():
        pages[day] = (md, {"edition": day.isoformat(), "source": src})
    for day in sorted(editions):
        for gap in range(1, MAX_REPEAT_GAP + 1):
            d = day + dt.timedelta(days=gap)
            if d in editions or d.weekday() not in (FRIDAY, SATURDAY):
                break
            md, src = editions[day]
            pages[d] = (md, {"edition": day.isoformat(), "source": src})

    written = skipped = repeats = 0
    for day, (md, meta) in sorted(pages.items()):
        day_dir = args.root / f"{day:%Y/%m/%d}"
        if not ours(day_dir):
            skipped += 1
            print(f"skip {day}: holds a page this tool did not write", file=sys.stderr)
            continue
        repeats += meta["edition"] != day.isoformat()
        changed = write_if_changed(day_dir / "index.fi.md", md)
        changed |= write_if_changed(day_dir / "edition.json", json.dumps(meta, ensure_ascii=False) + "\n")
        written += changed
    print(f"{len(editions)} broadcast(s) {min(editions)} .. {max(editions)}; "
          f"{len(pages)} page(s), {repeats} of them repeats; {written} changed, {skipped} skipped")


if __name__ == "__main__":
    main()
