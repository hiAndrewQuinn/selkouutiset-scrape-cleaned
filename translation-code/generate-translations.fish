#!/usr/bin/env fish

# This script is meant to be run with one argument, the Google Cloud project name.
set GCP_SELKOUUTISET_ARCHIVE_PROJECT $argv[1]

# Use `fd` to find all .md.json files and pipe the results to the while loop
fd '_request\...\...\.json' | while read -l file
    # Construct the name for the output file
    set output_file (string replace '_request' '_response' $file)

    # If the output file already exists, skip this file
    echo $file, $output_file
    if test -f $output_file
        set_color yellow
        echo "Skipping $file"
        set_color normal
        continue
    end

    # Execute the curl command and save the response
    curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "x-goog-user-project: $GCP_SELKOUUTISET_ARCHIVE_PROJECT" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d @$file \
        "https://translation.googleapis.com/language/translate/v2" \
        -o $output_file

    echo ---
    cat $output_file | jq
    echo ---

    set_color green
    echo "Translation saved to $output_file"
    set_color normal
end
