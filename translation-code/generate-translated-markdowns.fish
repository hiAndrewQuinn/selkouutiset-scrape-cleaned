#!/usr/bin/env fish

# Find all .en.json files and process them
find . -name '*index.en.md.json' | while read -l json_file
    echo "Processing $json_file"
    # Construct the Markdown file name
    set markdown_file (string replace ".en.md.json" ".en.md" $json_file)

    # Use jq and tr to process the JSON file and save the output to the Markdown file
    cat $json_file | jq -r '.data.translations[].translatedText' | tr -d '"' > $markdown_file

    echo "Created Markdown file: $markdown_file"
end
