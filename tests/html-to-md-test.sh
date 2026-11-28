#!/bin/sh
# Tests for lib/html-to-md.sh: how Yle's HTML becomes the archive's Markdown.
#
#   sh tests/html-to-md-test.sh            # any POSIX sh
#   busybox sh tests/html-to-md-test.sh
#
# Needs pandoc and perl. process.sh insists on one pandoc version (the stored
# Markdown was made with it); with another the test still runs but says so,
# since pandoc's output can differ between versions. Uses a temporary
# directory, removed at the end; no network. Exits non-zero if any case fails.

LIB=$(cd "$(dirname "$0")/.." && pwd)/lib/html-to-md.sh
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/html-to-md-test.XXXXXX") || exit 1
trap 'rm -rf "$ROOT"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); echo "  ok   $*"; }
no() { fail=$((fail + 1)); echo "  FAIL $*"; }

. "$LIB"

want_pandoc="pandoc 3.7.0.1"
have_pandoc=$(pandoc --version 2>/dev/null | head -n 1)
[ "$have_pandoc" = "$want_pandoc" ] || echo "NOTE: testing with '$have_pandoc', not '$want_pandoc' as process.sh requires."

IMG=https://img.img-cdn.yle.fi/crop_fill,w_767,h_431,dpr_1/f_auto/13-3-5453373

# page BODY: a minimal Yle-like page around BODY, converted; Markdown in $ROOT/out.md
page() {
  printf '<html><body><main><h2>Otsikko</h2><p>Ensimmäinen kappale.</p>%s<p>Toinen kappale.</p></main></body></html>\n' "$1" >"$ROOT/in.html"
  html_to_md <"$ROOT/in.html" >"$ROOT/out.md"
}
# has LINE: the output contains exactly this line
has() { grep -qxF -- "$1" "$ROOT/out.md"; }
# clean: the output passes the leftover-HTML check
clean() { md_html_leftovers "$ROOT/out.md" >/dev/null; }
# expect NAME CONDITION
expect() {
  if eval "$2"; then ok "$1"; else
    no "$1   [$2]"
    sed 's/^/    | /' "$ROOT/out.md"
  fi
}

echo "image with alt text (Yle's usual markup)"
page "<img alt=\"Lapsia leikkimässä.\" src=\"$IMG\" loading=\"lazy\" class=\"aw__sc-dklauk-0 LPzKX\"/>"
expect "becomes a Markdown image" 'has "![Lapsia leikkimässä.]($IMG)"'
expect "no HTML left" clean

echo "image with empty alt (the 2014/11/20 bug: it came out as a bare src=\"...\" line)"
page "<img alt=\"\" src=\"$IMG\" loading=\"lazy\" class=\"aw__sc-dklauk-0 LPzKX\"/>"
expect "becomes a Markdown image with empty alt" 'has "![]($IMG)"'
expect "no bare src= line" '! grep -q "src=" "$ROOT/out.md"'
expect "no HTML left" clean

echo "image with no alt attribute at all"
page "<img src=\"$IMG\" loading=\"lazy\" class=\"x\"/>"
expect "becomes a Markdown image with empty alt" 'has "![]($IMG)"'
expect "no HTML left" clean

echo "plain image (pandoc writes the Markdown itself)"
page "<img alt=\"Kuva\" src=\"$IMG\"/>"
expect "becomes a Markdown image" 'has "![Kuva]($IMG)"'

echo "alt text with quotation marks"
page "<img alt=\"Taideteos &quot;Where shall we go dancing tonight?&quot;\" src=\"$IMG\" class=\"x\"/>"
expect "kept, entity-encoded, as one image" 'has "![Taideteos &quot;Where shall we go dancing tonight?&quot;]($IMG)"'
expect "no HTML left" clean

echo "two images on one line, one without alt"
page "<p><img alt=\"\" src=\"$IMG-a\" class=\"x\"/><img alt=\"B\" src=\"$IMG-b\" class=\"x\"/></p>"
expect "both become Markdown images" 'grep -qF "![]($IMG-a)" "$ROOT/out.md" && grep -qF "![B]($IMG-b)" "$ROOT/out.md"'
expect "no HTML left" clean

echo "inline SVG icon (data: URI)"
page '<img alt="" src="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=" class="icon"/>'
expect "dropped entirely" '! grep -q "data:image" "$ROOT/out.md" && ! grep -q "!\[" "$ROOT/out.md"'
expect "no HTML left" clean

echo "text around the images survives"
page "<img alt=\"\" src=\"$IMG\" class=\"x\"/>"
expect "heading and paragraphs intact" 'has "## Otsikko" && has "Ensimmäinen kappale." && has "Toinen kappale."'

echo "the leftover check itself"
printf 'Teksti.\n\nsrc="%s"\n' "$IMG" >"$ROOT/bad.md"
expect "flags a bare src= line" '! md_html_leftovers "$ROOT/bad.md" >/dev/null'
printf '<div class="x">Teksti</div>\n' >"$ROOT/bad.md"
expect "flags a tag" '! md_html_leftovers "$ROOT/bad.md" >/dev/null'
printf 'Googlella on data- eli palvelinkeskus. Hän sanoi: "src on lyhenne".\n\n![](%s)\n' "$IMG" >"$ROOT/good.md"
expect "passes ordinary text and images" 'md_html_leftovers "$ROOT/good.md" >/dev/null'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
