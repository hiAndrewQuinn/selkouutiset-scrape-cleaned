#!/usr/bin/fish

fd '.*.md$' | python3 markdown2json.py

git add -A
set timestamp (date -u)
git commit -m "Generate translation JSONs: $timestamp" || exit 0
git push

popd
