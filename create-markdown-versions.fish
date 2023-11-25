#!/usr/bin/fish

set this_directory /home/andrew/Code/selkouutiset-scrape-cleaned
pushd $this_directory

# Pull the latest HEAD from selkouutiset-scrape.
git submodule update --remote selkouutiset-scrape/
cd selkouutiset-scrape/
git pull origin HEAD
cd $this_directory

set source_dir "./selkouutiset-scrape/"
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

    cat $source_file

    cat $source_file |
        pandoc -f html -t commonmark --wrap=none |
        sed -n '/## Radio/,$p' |
        sed '/Yle Selkouutiset kertoo uutiset helpolla suomen kielellä./Q' |
        sed '/^<div\|^<\/div/d' |
        sed '/^<span\|^<\/span/d' |
        pandoc -f commonmark -t html |
        sed '/^<ul>\|^<\/ul>/d' |
        sed '/^<li><a/d' |
        sed '/^<p><a href.*poddar/d' |
        sed '/<p>journalismia/d' |
        sed '/lukea uutiset samanaikaisesti alta/d' |
        pandoc -f html -t markdown --wrap=none |
        sed 's/{\.aw-zhx2sq \.hyCAoR}//g' >$dest_file
end

git add -A
set timestamp (date -u)
git commit -m "Latest data: $timestamp" || exit 0
git push

popd
