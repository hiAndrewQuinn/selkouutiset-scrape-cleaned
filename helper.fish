#!/bin/fish

git pull && git submodule update --remote

cat languages.txt | while read -l lang
    fd '.*.fi.md$' | python translation-code/markdown2json.py --target-lang=$lang
end

fish translation-code/generate-translations.fish

fd '_response\...\...\.json' | python translation-code/json2markdown.py

git add -A
git commit -m 'feat: New translations, $(date --iso-8601)'
git push
