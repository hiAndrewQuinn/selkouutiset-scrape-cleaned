#!/usr/bin/fish

source html2md.fish

set source_dir "./selkouutiset-scrape/"
set hash "./.hash"

touch $hash

for source_file in (find $source_dir -type f -name "*.html")
    if grep -q (sha1sum $source_file | awk '{print $2, $1}') $hash
        set_color yellow
        echo "no changes in" $source_file ", skipping."
        set_color normal
        continue # skip to the next iteration of the loop if the hash is found
    end

    echo "now doing $source_file."
    # append the hash to the hash file
    echo (sha1sum $source_file | awk '{print $2, $1}') >>$hash

    set dest_dir (echo $source_file | sed "s|$source_dir||" | sed 's|/[^/]*$||')
    mkdir -p $dest_dir

    set dest_file "$dest_dir/_index.fi.md"

    html2md $source_file $dest_file

    # Heuristic: Almost all of our articles have over 50 lines in them after
    # processing with html2md. If we get a file with under 30 lines, something
    # probably went wrong, and we should raise an error.
    if test (wc -l $dest_file | awk '{print $1}') -lt 30
        set_color red
        echo "Error: $dest_file has less than 30 lines. Check it to see if something went wrong here."
        exit 1
    else
        set_color green
        echo "Success! $dest_file has over 30 lines."
        set_color normal
    end
end
