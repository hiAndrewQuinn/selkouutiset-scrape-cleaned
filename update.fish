#!/usr/bin/fish

# Don't do anything if there's uncommitted work here.
test (git status --porcelain | wc -l) -eq 0 || exit 0
echo "No uncommitted work found -- moving on."

set previous_branch (git branch | grep '*' | awk '{print $2}')
git checkout master
git pull

test -d .git/modules || git submodule update --init --remote
git submodule update --remote

git add -A
set timestamp (date -u)
git commit -m "Update submodules: $timestamp"
git push

git checkout $previous_branch
