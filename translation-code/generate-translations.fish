#!/usr/bin/env fish

# Use `fd` to find all .md.json files and pipe the results to the while loop
fd '_request\...\...\.json' | while read -l file
    # Construct the name for the output file
    set output_file (string replace '_request' '_response' $file)

    # If the output file already exists, skip this file
    echo $file, $output_file
    if test -f $output_file
        echo "Skipping $file"
        continue
    end

    # Execute the curl command and save the response
    curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "x-goog-user-project: andrews-selkouutiset-archive" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d @$file \
        "https://translation.googleapis.com/language/translate/v2" \
        -o $output_file

    echo ---
    cat $output_file | jq
    echo ---

    echo "Translation saved to $output_file"
end
