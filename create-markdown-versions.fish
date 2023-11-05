#!/usr/bin/fish

git submodule update

set source_dir "./selkouutiset-scrape-dirty/"
set hash "./.hash"

touch $hash

for source_file in (find $source_dir -type f -name "*.html")
    if grep -q (sha1sum $source_file) $hash
        echo "No changes in" $source_file ", skipping."
        continue # Skip to the next iteration of the loop if the hash is found
    end

    echo "Now doing $source_file."
    # Append the hash to the hash file
    echo (sha1sum $source_file) >>$hash

    set dest_dir (echo $source_file | sed "s|$source_dir||" | sed 's|/[^/]*$||')
    mkdir -p $dest_dir

    set dest_file "$dest_dir/_index.md"

    cat $source_file |
        pandoc -f html -t commonmark |
        sed -n '0,/^<div class="ArticleWrapper/!p' |
        sed '/^<div\|^<\/div/d' |
        sed '/^<span\|^<\/span/d' |
        pandoc -f commonmark -t html |
        sed '/^<ul>\|^<\/ul>/d' |
        sed '/^<li><a/d' |
        sed '/^<p><a href.*poddar/d' |
        sed '/<p>journalismia/d' |
        sed '/Voit lukea uutiset samanaikaisesti alta/d' |
        pandoc -f html -t commonmark >$dest_file
end
