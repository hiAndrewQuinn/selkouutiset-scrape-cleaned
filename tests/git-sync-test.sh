#!/bin/sh
# Tests for lib/git-sync.sh, against throwaway local repositories.
#
#   sh tests/git-sync-test.sh            # any POSIX sh
#   busybox sh tests/git-sync-test.sh    # what the box runs
#
# Each case builds a bare "github", a "box" clone and a "dev" clone in a fresh
# temporary directory, which is removed at the end (pass or fail). Needs git;
# nothing outside the temporary directory is touched, and no network is used.
# Exits non-zero if any case fails.

LIB=$(cd "$(dirname "$0")/.." && pwd)/lib/git-sync.sh
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/git-sync-test.XXXXXX") || exit 1
trap 'rm -rf "$ROOT"' EXIT
pass=0 fail=0

log_message() { echo "    | $*"; }
ok() { pass=$((pass + 1)); echo "  ok   $*"; }
no() { fail=$((fail + 1)); echo "  FAIL $*"; }
check() { if eval "$2"; then ok "$1"; else no "$1   [$2]"; fi; }

GIT_REMOTE=origin GIT_BRANCH=master GIT_RETRY_SLEEP=0 GIT_NET_ATTEMPTS=2 GIT_NET_TIMEOUT=20
. "$LIB"

g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=master -c protocol.file.allow=always "$@"; }
commit() { # dir file text
  (cd "$1" && printf '%s\n' "$3" >"$2" && g add "$2" && g commit -qm "$2: $3")
}
fresh() { # new github/box/dev under $ROOT/$1, one shared commit
  d="$ROOT/$1"
  mkdir -p "$d" && g init -q --bare "$d/github.git"
  g clone -q "$d/github.git" "$d/dev" 2>/dev/null
  commit "$d/dev" a.txt base && (cd "$d/dev" && g push -q origin master)
  g clone -q "$d/github.git" "$d/box"
  BOX="$d/box" DEV="$d/dev"
}
in_box() { (cd "$BOX" && "$@"); }
head_of() { git -C "$1" rev-parse HEAD; }
upstream() { git -C "$BOX" rev-parse origin/master; }

echo "level"
fresh level
check "sync succeeds" 'in_box git_sync'
check "push with nothing new succeeds" 'in_box git_push'

echo "behind (a PR merged on GitHub)"
fresh behind
commit "$DEV" b.txt pr && (cd "$DEV" && g push -q)
check "sync succeeds" 'in_box git_sync'
check "box fast-forwarded to github" '[ "$(head_of "$BOX")" = "$(head_of "$DEV")" ]'

echo "ahead (box committed, not pushed)"
fresh ahead
commit "$BOX" c.txt local
before=$(head_of "$BOX")
check "sync succeeds and leaves HEAD" 'in_box git_sync && [ "$(head_of "$BOX")" = "$before" ]'
check "push sends it" 'in_box git_push && [ "$(git -C "$ROOT/ahead/github.git" rev-parse master)" = "$before" ]'

echo "diverged, different files (this morning's case)"
fresh diverged
commit "$BOX" box.txt nightly
commit "$DEV" pr.txt merged && (cd "$DEV" && g push -q)
check "sync rebases" 'in_box git_sync'
check "box keeps both changes" '[ -f "$BOX/box.txt" ] && [ -f "$BOX/pr.txt" ]'
check "history is linear (no merge commit)" '[ -z "$(git -C "$BOX" rev-list --merges HEAD)" ]'
check "github's commit is an ancestor" 'git -C "$BOX" merge-base --is-ancestor "$(head_of "$DEV")" HEAD'
check "push succeeds" 'in_box git_push'

echo "diverged, same file (conflict)"
fresh conflict
commit "$BOX" a.txt box-version
commit "$DEV" a.txt dev-version && (cd "$DEV" && g push -q)
before=$(head_of "$BOX")
check "sync fails" '! in_box git_sync'
check "HEAD untouched" '[ "$(head_of "$BOX")" = "$before" ]'
check "no rebase left in progress" '[ ! -d "$BOX/.git/rebase-merge" ] && [ ! -d "$BOX/.git/rebase-apply" ]'
check "working tree clean" '[ -z "$(git -C "$BOX" status --porcelain)" ]'

echo "behind, with uncommitted work in the tree"
fresh dirty
commit "$DEV" b.txt pr && (cd "$DEV" && g push -q)
printf 'half-written\n' >"$BOX/new.md"
printf 'edited\n' >"$BOX/a.txt"
check "sync succeeds" 'in_box git_sync'
check "fast-forwarded" '[ "$(head_of "$BOX")" = "$(head_of "$DEV")" ]'
check "uncommitted edit kept" '[ "$(cat "$BOX/a.txt")" = edited ]'
check "untracked file kept" '[ -f "$BOX/new.md" ]'

echo "push rejected because github moved during the run"
fresh race
commit "$BOX" box.txt nightly
commit "$DEV" pr.txt merged && (cd "$DEV" && g push -q)
check "git_push re-syncs and succeeds" 'in_box git_push'
check "github has both" 'git -C "$ROOT/race/github.git" show master:box.txt >/dev/null && git -C "$ROOT/race/github.git" show master:pr.txt >/dev/null'

echo "network failure"
fresh offline
in_box git remote set-url origin "$ROOT/does-not-exist.git"
check "sync fails without hanging" '! in_box git_sync'

echo "network timeout"
fresh slow
in_box git remote set-url origin "ssh://example.invalid/x.git"
start=$(date +%s)
check "sync gives up" '! (cd "$BOX" && GIT_SSH_COMMAND="sleep 30 #" GIT_NET_TIMEOUT=1 git_sync)'
check "within the timeouts (<= 10s)" '[ $(($(date +%s) - start)) -le 10 ]'

echo "submodule checked out away from its recorded commit (the cleaned repo's state)"
fresh sub
g init -q --bare "$ROOT/sub/inner.git"
g clone -q "$ROOT/sub/inner.git" "$ROOT/sub/inner" 2>/dev/null
commit "$ROOT/sub/inner" x.txt one && (cd "$ROOT/sub/inner" && g push -q origin master)
(cd "$DEV" && g submodule add -q "$ROOT/sub/inner.git" inner && g commit -qm "add submodule" && g push -q)
(cd "$BOX" && g pull -q && g submodule update -q --init)
commit "$ROOT/sub/inner" x.txt two && (cd "$ROOT/sub/inner" && g push -q)
(cd "$BOX" && g submodule update -q --remote inner)
commit "$BOX" box.txt nightly
commit "$DEV" pr.txt merged && (cd "$DEV" && g push -q)
check "sync rebases past the moved submodule" 'in_box git_sync'
check "submodule checkout left where it was" '[ "$(git -C "$BOX/inner" log -1 --format=%s)" = "x.txt: two" ]'

echo "free space"
fresh space
check "passes with a 1 MB minimum" '(cd "$BOX" && MIN_FREE_MB=1 check_free_space)'
check "fails with an impossible minimum" '! (cd "$BOX" && MIN_FREE_MB=999999999 check_free_space)'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
