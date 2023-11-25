#!/usr/bin/fish

set this_directory /home/andrew/Code/selkouutiset-scrape-cleaned
pushd $this_directory

fd '.*.md$' | python3 markdown2json.py

git add -A
set timestamp (date -u)
git commit -m "Generate translation JSONs: $timestamp" || exit 0
git push

popd
