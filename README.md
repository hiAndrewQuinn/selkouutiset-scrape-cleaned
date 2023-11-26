# `selkoutiset-scrape-cleaned`

How do the raw HTML files in [selkouutiset-scrape](https://github.com/hiAndrewQuinn/selkouutiset-scrape) get cleaned up in to nice, easy-to-read Markdown files? This repository is how, using a combination of shell scripts and (as the needs of the project grew) Python as well.

Here I'm going to outline how to do all of these steps **by hand**. If you want to run the whole process, you can just run the shell script `run.sh` (which is what I do).

## Quickstart

```fish
# You can try this in /tmp if you want to just see it for yourself.

git clone https://github.com/hiAndrewQuinn/selkouutiset-scrape-cleaned.git
cd selkouutiset-scrape-cleaned

fish update.fish

rm .hash
rm -rf 20*/
fish create-markdown-versions.fish


```

## Detailed instructions

### 1. Update the submodules to the latest commit

`selkouutiset-scrape-cleaned` uses `selkouutiset-scrape` as a Git submodule. So the first thing to do on a fresh `clone` is run

```fish
fish update.fish
```

while in the root of the `cleaned` repo. This will both initialize and update the submodules for us.

This `update.fish` defaults to doing nothing if the Git repo in question has any uncommitted work, so it's pretty safe to run on a loop.

### Turn the (Finnish-language) HTML into (Finnish-language) Markdown

Once we have a fresh set of HTML, we can then run

```fish
fish create-markdown-versions.fish
```

again while in the root of the `cleaned` repo, to run all of our HTML files through the `pandoc` and `sed` filters that eventually produce our nice and clean `_index.fi.md` files.

### (TBD) Create translations with the Google Translation API
