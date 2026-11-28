#!/bin/sh
# Checks every stored page for HTML that survived the conversion to Markdown.
#
#   sh tests/content-lint.sh               # from anywhere; checks the whole repo
#
# Catches the whole class of bug where a page shows raw markup, such as the
# bare  src="https://img.img-cdn.yle.fi/..."  lines that alt-less images once
# produced (see lib/html-to-md.sh). Looks at every index.fi.md and index.en.md,
# and at the translation request/response JSON the English pages are rebuilt
# from. Read-only and offline. Exits non-zero, listing each offending line, if
# anything is found.

REPO=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO/lib/html-to-md.sh"
cd "$REPO" || exit 1
status=0

pages=$(find [12][09][0-9][0-9] -name 'index.*.md' 2>/dev/null | sort)
if [ -z "$pages" ]; then
  echo "FAIL no pages found under $REPO"
  exit 1
fi
count=$(printf '%s\n' "$pages" | wc -l)

# shellcheck disable=SC2086 # the page paths have no spaces
if out=$(md_html_leftovers $pages); then
  echo "ok   no raw HTML in $count page(s)"
else
  echo "FAIL raw HTML in pages:"
  printf '%s\n' "$out" | sed 's/^/    /'
  status=1
fi

# The same marks inside a JSON string: "src=\"https://...\"".
if out=$(find [12][09][0-9][0-9] -name '_re*.fi.en.json' -exec grep -nHE '"[[:space:]]*(src|alt|srcset|class)=\\"|<img\b' {} + 2>/dev/null); then
  echo "FAIL raw HTML in translation JSON:"
  printf '%s\n' "$out" | sed 's/^/    /'
  status=1
else
  echo "ok   no raw HTML in the translation JSON"
fi

exit $status
