#!/bin/sh
# Tests for lib/git-sync.sh, against throwaway local repositories.
#
#   sh tests/git-sync-test.sh            # any POSIX sh
#   busybox sh tests/git-sync-test.sh
#
# Each case builds a bare "github", a "local" clone and a "dev" clone in a fresh
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
# The library's rebases commit, so git needs an identity even where none is
# configured (a CI runner). Set one for this test only.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
. "$LIB"

g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=master -c protocol.file.allow=always "$@"; }
commit() { # dir file text
  (cd "$1" && printf '%s\n' "$3" >"$2" && g add "$2" && g commit -qm "$2: $3")
}
fresh() { # new github/local/dev under $ROOT/$1, one shared commit
  d="$ROOT/$1"
  mkdir -p "$d" && g init -q --bare "$d/github.git"
  g clone -q "$d/github.git" "$d/dev" 2>/dev/null
  commit "$d/dev" a.txt base && (cd "$d/dev" && g push -q origin master)
  g clone -q "$d/github.git" "$d/local"
  LOCAL="$d/local" DEV="$d/dev"
}
in_local() { (cd "$LOCAL" && "$@"); }
head_of() { git -C "$1" rev-parse HEAD; }
upstream() { git -C "$LOCAL" rev-parse origin/master; }

echo "level"
fresh level
check "sync succeeds" 'in_local git_sync'
check "push with nothing new succeeds" 'in_local git_push'

echo "behind (a PR merged on GitHub)"
fresh behind
commit "$DEV" b.txt pr && (cd "$DEV" && g push -q)
check "sync succeeds" 'in_local git_sync'
check "local fast-forwarded to github" '[ "$(head_of "$LOCAL")" = "$(head_of "$DEV")" ]'

echo "ahead (local committed, not pushed)"
fresh ahead
commit "$LOCAL" c.txt local
before=$(head_of "$LOCAL")
check "sync succeeds and leaves HEAD" 'in_local git_sync && [ "$(head_of "$LOCAL")" = "$before" ]'
check "push sends it" 'in_local git_push && [ "$(git -C "$ROOT/ahead/github.git" rev-parse master)" = "$before" ]'

echo "diverged, different files "
fresh diverged
commit "$LOCAL" local.txt nightly
commit "$DEV" pr.txt merged && (cd "$DEV" && g push -q)
check "sync rebases" 'in_local git_sync'
check "local keeps both changes" '[ -f "$LOCAL/local.txt" ] && [ -f "$LOCAL/pr.txt" ]'
check "history is linear (no merge commit)" '[ -z "$(git -C "$LOCAL" rev-list --merges HEAD)" ]'
check "github's commit is an ancestor" 'git -C "$LOCAL" merge-base --is-ancestor "$(head_of "$DEV")" HEAD'
check "push succeeds" 'in_local git_push'

echo "diverged, same file (conflict)"
fresh conflict
commit "$LOCAL" a.txt local-version
commit "$DEV" a.txt dev-version && (cd "$DEV" && g push -q)
before=$(head_of "$LOCAL")
check "sync fails" '! in_local git_sync'
check "HEAD untouched" '[ "$(head_of "$LOCAL")" = "$before" ]'
check "no rebase left in progress" '[ ! -d "$LOCAL/.git/rebase-merge" ] && [ ! -d "$LOCAL/.git/rebase-apply" ]'
check "working tree clean" '[ -z "$(git -C "$LOCAL" status --porcelain)" ]'

echo "behind, with uncommitted work in the tree"
fresh dirty
commit "$DEV" b.txt pr && (cd "$DEV" && g push -q)
printf 'half-written\n' >"$LOCAL/new.md"
printf 'edited\n' >"$LOCAL/a.txt"
check "sync succeeds" 'in_local git_sync'
check "fast-forwarded" '[ "$(head_of "$LOCAL")" = "$(head_of "$DEV")" ]'
check "uncommitted edit kept" '[ "$(cat "$LOCAL/a.txt")" = edited ]'
check "untracked file kept" '[ -f "$LOCAL/new.md" ]'

echo "push rejected because github moved during the run"
fresh race
commit "$LOCAL" local.txt nightly
commit "$DEV" pr.txt merged && (cd "$DEV" && g push -q)
check "git_push re-syncs and succeeds" 'in_local git_push'
check "github has both" 'git -C "$ROOT/race/github.git" show master:local.txt >/dev/null && git -C "$ROOT/race/github.git" show master:pr.txt >/dev/null'

echo "push keeps failing (no push access), fetch fine"
fresh denied
commit "$LOCAL" local.txt nightly
in_local git remote set-url --push origin "$ROOT/denied/no-such-repo.git"
# git_push calls git_sync between attempts, and git_sync calls git_net. They
# once shared a retry counter, so every sync reset git_push's and it retried
# forever, holding the caller's lock. Run it in its own shell under a timeout.
start=$(date +%s)
check "push gives up (does not loop)" '! (cd "$LOCAL" && GIT_REMOTE=origin GIT_BRANCH=master GIT_RETRY_SLEEP=0 GIT_NET_ATTEMPTS=3 timeout 20 sh -c '"'"'log_message() { echo "    | $*"; }; . "$1"; git_push'"'"' sh "$LIB")'
check "it gave up by itself, not by the timeout (<= 10s)" '[ $(($(date +%s) - start)) -le 10 ]'
check "the commit is still here" '[ -f "$LOCAL/local.txt" ]'

echo "network failure"
fresh offline
in_local git remote set-url origin "$ROOT/does-not-exist.git"
check "sync fails without hanging" '! in_local git_sync'

echo "network timeout"
fresh slow
in_local git remote set-url origin "ssh://example.invalid/x.git"
start=$(date +%s)
check "sync gives up" '! (cd "$LOCAL" && GIT_SSH_COMMAND="sleep 30 #" GIT_NET_TIMEOUT=1 git_sync)'
check "within the timeouts (<= 10s)" '[ $(($(date +%s) - start)) -le 10 ]'

echo "submodule checked out away from its recorded commit"
fresh sub
g init -q --bare "$ROOT/sub/inner.git"
g clone -q "$ROOT/sub/inner.git" "$ROOT/sub/inner" 2>/dev/null
commit "$ROOT/sub/inner" x.txt one && (cd "$ROOT/sub/inner" && g push -q origin master)
(cd "$DEV" && g submodule add -q "$ROOT/sub/inner.git" inner && g commit -qm "add submodule" && g push -q)
(cd "$LOCAL" && g pull -q && g submodule update -q --init)
commit "$ROOT/sub/inner" x.txt two && (cd "$ROOT/sub/inner" && g push -q)
(cd "$LOCAL" && g submodule update -q --remote inner)
commit "$LOCAL" local.txt nightly
commit "$DEV" pr.txt merged && (cd "$DEV" && g push -q)
check "sync rebases past the moved submodule" 'in_local git_sync'
check "submodule checkout left where it was" '[ "$(git -C "$LOCAL/inner" log -1 --format=%s)" = "x.txt: two" ]'

echo "free space"
fresh space
check "passes with a 1 MB minimum" '(cd "$LOCAL" && MIN_FREE_MB=1 check_free_space)'
check "fails with an impossible minimum" '! (cd "$LOCAL" && MIN_FREE_MB=999999999 check_free_space)'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
