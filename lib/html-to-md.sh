# html-to-md.sh: turn one of Yle's Selkouutiset pages into the archive's Markdown.
#
# Sourced (never run) by process.sh, and by tests/html-to-md-test.sh, which
# pins its behaviour. POSIX sh; needs pandoc (the exact version process.sh
# checks for) and perl.
#
# Careful: the published index.fi.md files are this function's output, and a
# day is only re-translated (paid) when its regenerated Markdown differs from
# the stored one. Any change here that alters the output for existing pages
# must come with a matching repair of the stored files (index.fi.md, and the
# translation's request/response JSON and index.en.md), or the next
# regeneration of those days pays to translate them again.

# html_to_md: HTML on stdin, Markdown on stdout.
html_to_md() {
  pandoc --from=html --to=commonmark --wrap=none |
    perl -CSDA -pe 's{!\[[^\]]*\]\(data:image/svg\+xml;base64,[^)]*\)}{}g' |
    perl -CSDA -ne 'print unless /^Artikkeli on yli (?:\d+ vuotta|vuoden) vanha\s*$/' |
    perl -CSDA -pe 's{src="data:image/svg\+xml;base64,[^"]*"}{}gi' |
    # pandoc leaves an <img> as raw HTML when it has attributes Markdown cannot
    # hold (Yle's class and loading). Rewrite it as a Markdown image; an image
    # with no alt text (alt="" is dropped by pandoc) gets an empty one. Take the
    # whole tag before matching inside it: afterwards $& is the inner match
    # (src="..."), which once turned every alt-less image into a bare
    # src="https://..." line on the page.
    perl -CSDA -pe 's{<img\s+([^>]+)>}{ my $tag_img = $&; my $attrs_img = $1; my $src_img = ($attrs_img =~ m{src="([^"]*)"}i) ? $1 : undef; my $alt_img = ($attrs_img =~ m{alt="([^"]*)"}i) ? $1 : ""; defined $src_img ? sprintf("![%s](%s)", $alt_img, $src_img) : $tag_img }gei' |
    perl -CSDA -pe 's{</?(?!img.*yle\.fi)[^>]*>}{}gi' |
    perl -CSDA -0777 -pe 's/^(\s*\n)+//g' |
    perl -CSDA -0777 -pe 's/(\s*\n)*(Tulosta|Jaa)(\s*\n(Tulosta|Jaa))*\s*$//' |
    perl -CSDA -0777 -pe 's/\n{3,}/\n\n/g' |
    perl -CSDA -0777 -pe 's/\s*$/\n/ if /./; $_ = "" if $_ eq "\n";'
}

# The marks of HTML that survived the conversion: an attribute alone at the
# start of a line (as src="..." did), or a tag. Markdown from Yle's pages
# should contain neither.
MD_HTML_LEFTOVER_RE='^[[:space:]]*(src|alt|srcset|class|loading|href|style|width|height|data-[a-z-]+)="|<(img|div|span|figure|figcaption|picture|source|svg|button|script|iframe|a)\b|</(div|span|figure|a|p)>'

# md_html_leftovers FILE...: print file:line:text for every leftover, and
# succeed only when there are none.
md_html_leftovers() {
  ! grep -nHE -- "$MD_HTML_LEFTOVER_RE" "$@"
}
