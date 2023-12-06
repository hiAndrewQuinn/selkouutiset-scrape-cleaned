#!/bin/fish

git sumbodule update --remote
git pull

cat languages.txt | while read -l lang
    fd '.*.fi.md$' | python translation-code/markdown2json.py --target-lang=$lang
end

fish translation-code/generate-translations.fish

fd '_response\...\...\.json' | python translation-code/json2markdown.py
