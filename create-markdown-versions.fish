#!/usr/bin/fish

set this_directory /home/andrew/Code/Github/selkouutiset-scrape-cleaned
pushd $this_directory

# Pull the latest HEAD from selkouutiset-scrape.
cd selkouutiset-scrape-dirty/
git pull origin HEAD
cd -

set source_dir "./selkouutiset-scrape-dirty/"
set hash "./.hash"

touch $hash

for source_file in (find $source_dir -type f -name "*.html")
    if grep -q (sha1sum $source_file) $hash
        echo "no changes in" $source_file ", skipping."
        continue # skip to the next iteration of the loop if the hash is found
    end

    echo "now doing $source_file."
    # append the hash to the hash file
    echo (sha1sum $source_file) >>$hash

    set dest_dir (echo $source_file | sed "s|$source_dir||" | sed 's|/[^/]*$||')
    mkdir -p $dest_dir

    set dest_file "$dest_dir/_index.md"

    cat $source_file |
        pandoc -f html -t commonmark |
        sed -n '0,/^<div class="articlewrapper/!p' |
        sed '/^<div\|^<\/div/d' |
        sed '/^<span\|^<\/span/d' |
        pandoc -f commonmark -t html |
        sed '/^<ul>\|^<\/ul>/d' |
        sed '/^<li><a/d' |
        sed '/^<p><a href.*poddar/d' |
        sed '/<p>journalismia/d' |
        sed '/voit lukea uutiset samanaikaisesti alta/d' |
        pandoc -f html -t commonmark >$dest_file
end

git add -A
set timestamp (date -u)
git commit -m "Latest data: $timestamp" || exit 0
git push

popd
