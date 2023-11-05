#!/usr/bin/fish

git submodule update

set source_dir "./selkouutiset-scrape-dirty/"

for source_file in (find $source_dir -type f -name "*.html")
    set dest_dir (echo $source_file | sed "s|$source_dir||" | sed 's|/[^/]*$||')
    if not test -d $dest_dir
        mkdir -p $dest_dir
        # Check if the directory was created successfully
        if not test $status -eq 0
            echo "Failed to create" $dest_dir
            continue # Skip to the next iteration of the loop if directory creation failed
        end
        echo $dest_dir "created."
    end

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
