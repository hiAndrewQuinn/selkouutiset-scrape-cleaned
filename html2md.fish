#!/usr/bin/fish

function html2md
    set source_file $argv[1]
    set dest_file $argv[2]

    cat $source_file |
        pandoc -f html -t commonmark --wrap=none |
        sed -n '/# TV/,$p' |
        tac |
        sed '0,/Yle Selkouutiset kertoo uutiset helpolla suomen kielellä./d' |
        tac |
        sed '/^<div\|^<\/div/d' |
        sed '/^<span\|^<\/span/d' |
        pandoc -f commonmark -t html |
        sed '/^<ul>\|^<\/ul>/d' |
        sed '/^<li><a/d' |
        sed '/^<p><a href.*poddar/d' |
        sed '/<p>journalismia/d' |
        sed '/lukea uutiset samanaikaisesti alta/d' |
        pandoc -f html -t markdown --wrap=none |
        sed 's/{\.aw-zhx2sq \.hyCAoR}//g' |
        sed '/Yle Selkouutiset kertoo uutiset helpolla suomen kielellä/Q' |
        cat >$dest_file
end
