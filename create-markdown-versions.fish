#!/usr/bin/fish

source html2md.fish

set source_dir "./selkouutiset-scrape/"
set hash "./.hash"

touch $hash

for source_file in (find $source_dir -type f -name "*.html")
    if grep -q (sha1sum $source_file | awk '{print $2, $1}') $hash
        echo "no changes in" $source_file ", skipping."
        continue # skip to the next iteration of the loop if the hash is found
    end

    echo "now doing $source_file."
    # append the hash to the hash file
    echo (sha1sum $source_file | awk '{print $2, $1}') >>$hash

    set dest_dir (echo $source_file | sed "s|$source_dir||" | sed 's|/[^/]*$||')
    mkdir -p $dest_dir

    set dest_file "$dest_dir/_index.fi.md"

    html2md $source_file $dest_file
end
