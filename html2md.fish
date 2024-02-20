#!/usr/bin/fish

function process_tv_file
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
        sed '/Yle Selkouutiset kertoo uutiset helpolla suomen kielellä/Q'
end

function process_radio_file
    sed -n '/# Radio/,$p' |
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
        sed '/Yle Selkouutiset kertoo uutiset helpolla suomen kielellä/Q'
end

function html2md
    set source_file $argv[1]
    set dest_file $argv[2]

    set tmp_md_file (mktemp).UNPROCESSED.md
    pandoc -f html -t commonmark --wrap=none $source_file >$tmp_md_file

    set has_tv (grep -q "# TV" $tmp_md_file; and echo true; or echo false)
    set has_radio (grep -q "# Radio" $tmp_md_file; and echo true; or echo false)

    if not $has_tv; and not $has_radio
        set_color red
        echo "No title found $source_file"
        set_color normal
    else if $has_tv; and $has_radio
        set_color yellow
        echo "Both TV and Radio found $source_file."
        set_color normal

        # We probably want to see the actual differences, so we'll generate the files first.
        set dest_file_tv (mktemp).TV.md
        set dest_file_radio (mktemp).RADIO.md

        cat $tmp_md_file | process_tv_file >$dest_file_tv
        cat $tmp_md_file | process_radio_file >$dest_file_radio

        set choices $dest_file_tv\n$dest_file_radio\n$tmp_md_file
        set selection (echo $choices | fzf --prompt="Which pipeline should we use?" --preview="bat --color=always -pp {}" --preview-window=right:50%)

        switch $selection
            case TV
                cat $dest_file_tv >$dest_file
            case Radio
                cat $dest_file_radio >$dest_file
        end
    else if $has_tv
        set_color green
        echo "# TV :: $source_file"
        set_color normal
        cat $source_file | process_tv_file >$dest_file
    else if $has_radio
        set_color blue
        echo "Radio $source_file"
        set_color normal
        cat $source_file | process_radio_file >$dest_file
    end
end
