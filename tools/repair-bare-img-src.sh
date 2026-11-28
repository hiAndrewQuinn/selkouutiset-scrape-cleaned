#!/bin/sh
# repair-bare-img-src.sh: fix the stored pages hit by the alt-less image bug.
#
# Until lib/html-to-md.sh was fixed, an image with no alt text came out of the
# HTML -> Markdown step as a bare line  src="https://img.img-cdn.yle.fi/..."
# instead of  ![](https://img.img-cdn.yle.fi/...)  and the line was carried
# into the translation request, Google's response and index.en.md. This
# rewrites that line to what the fixed conversion produces, in all four files,
# so the pages render the image and a later regeneration finds the Markdown
# unchanged (no paid re-translation).
#
#   sh tools/repair-bare-img-src.sh        # from the repository root
#
# Touches only files that contain the bad line; safe to run again (a second
# run changes nothing). Makes no network calls.
set -eu
cd "$(dirname "$0")/.."
n=0
for f in $(grep -rlE --include=index.fi.md --include=index.en.md '^src="https://[^" ]+"$' 2006 2007 2008 2009 20[1-9][0-9] 2>/dev/null); do
  perl -i -pe 's{^src="(https://[^" ]+)"$}{![]($1)}' "$f"
  n=$((n + 1))
done
for f in $(grep -rlE --include=_request.fi.en.json --include=_response.fi.en.json '"src=\\"https://[^"\\ ]+\\""' 20[0-9][0-9] 2>/dev/null); do
  perl -i -pe 's{"src=\\"(https://[^"\\ ]+)\\""}{"![]($1)"}g' "$f"
  n=$((n + 1))
done
echo "repaired $n file(s)"
