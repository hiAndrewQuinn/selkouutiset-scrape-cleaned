# Running on the box

The archive is kept up to date by a Raspberry Pi (`box`, 4 GB) running piCore
(Tiny Core Linux) and BusyBox. Two scripts do the work, one per repository:

| when (cron) | script | repository on the box | does |
|---|---|---|---|
| :50 hourly | `process.sh` (this repo) | `/home/tc/selkouutiset-scrape-cleaned` | new scrape → Markdown → (capped) translation → commit → push |
| :35 hourly | `scripts/update.sh` (selkouutiset-archive) | `/home/tc/selkouutiset-archive` | point `content` at the newest cleaned commit → commit → push; GitHub Actions deploys the site |

The scrape itself runs in GitHub Actions (selkouutiset-scrape), not here.

## Things about the box that shape the scripts

- **The filesystem is RAM.** `/` and `/home` are a 3.3 GB tmpfs; the three
  checkouts, the Google Cloud SDK and everything else live in memory. A full
  filesystem is a machine out of memory. Both scripts refuse to start with
  less than `MIN_FREE_MB` (default 100) free, and git is told to repack with
  one thread and a 64 MB window so a `gc --auto` after a big commit cannot
  balloon.
- **Persistence is a backup.** Tiny Core restores `/home`, `/opt` and the
  crontab at boot from `mydata.tgz` on the SD card, written only when someone
  runs `filetool.sh -b`. Anything changed since the last backup (including
  these scripts and the crontab) comes back at its backed-up version after a
  reboot, and `/opt/bootlocal.sh` then `git pull --rebase`s each checkout once.
  The scripts' own sync makes them recover from a stale restore by
  themselves, from the first run after the restored copy is new enough to
  have it.
- **BusyBox.** `sh` is ash; `ps`, `df`, `timeout` are BusyBox applets. The
  scripts are POSIX sh, use `df -Pk`, and `timeout SECS PROG`.

## Staying in step with GitHub (`lib/git-sync.sh`)

Changes reach `master`/`main` from two places: the box's hourly commits, and
PRs merged on GitHub. The box used to only push, so a merged PR left it
behind, its next push was rejected, and every run after that failed the same
way. Both scripts now, under their own lock:

1. check free space;
2. **sync**: fetch, then
   - level → nothing; ahead → nothing (the push sends it);
   - behind → fast-forward;
   - diverged → rebase the box's commits onto GitHub's (`--autostash` carries
     uncommitted files across). If that conflicts, the rebase is aborted, the
     checkout is left exactly as it was, and the run stops with
     `CRITICAL ERROR: could not rebase` in the log: that one needs a human.
3. do their work and commit;
4. **push**; if rejected because GitHub moved during the run, sync and retry
   (3 tries). A commit whose push still fails stays on the box and goes out
   with the next run, which pushes unpushed commits even when it has nothing
   new of its own.

Every network call runs under `timeout` (300 s) with retries, and git never
prompts (`GIT_TERMINAL_PROMPT=0`), so a hung connection cannot wedge cron.

A newer `process.sh` taken in by the sync applies from the next run: the
running shell keeps reading the file it started with.

The library is identical in both repositories (`lib/git-sync.sh`); keep them
so. Its tests run anywhere with git and a POSIX sh, including on the box:

```sh
busybox sh tests/git-sync-test.sh     # 28 cases; temp repos, no network
```

## Locks

| lock file | held by |
|---|---|
| `/tmp/selkouutiset-process.lock` | `process.sh`; the cleaned repo's log trim |
| `/tmp/selkouutiset-archive-update.lock` | `scripts/update.sh`; the archive's log trim |

A run that finds its lock taken exits at once ("Another … run still holds").
To do anything by hand in a checkout while cron is live, take the same lock:

```sh
cd /home/tc/selkouutiset-scrape-cleaned
flock -n /tmp/selkouutiset-process.lock git status   # fails at once if a run is active
```

## Running by hand

Both are safe to run at any time, any number of times; with nothing new they
change nothing.

```sh
cd /home/tc/selkouutiset-scrape-cleaned && ./process.sh >> activity.log 2>&1
/home/tc/selkouutiset-archive/scripts/update.sh >> /home/tc/selkouutiset-archive/activity.log 2>&1
```

`process.sh` always ends its log with the line
`Translate API usage this run: N paid translation(s) (cap 3) …`, however the
run ends. The spending guards (`TRANSLATE_FROM`, `MAX_API_TRANSLATIONS`) are
described at the top of `process.sh`.

## The crontab (`crontab -l` as `tc`)

```
50 * * * * cd /home/tc/selkouutiset-scrape-cleaned && ./process.sh >> /home/tc/selkouutiset-scrape-cleaned/activity.log 2>&1
35 * * * * /home/tc/selkouutiset-archive/scripts/update.sh >> /home/tc/selkouutiset-archive/activity.log 2>&1
0 * * * * cd /home/tc/selkouutiset-scrape/ && git pull
5 0 * * * cd /home/tc/selkouutiset-scrape-cleaned && flock /tmp/selkouutiset-process.lock sh -c 'tail -n 1000 activity.log > activity.log.tmp && mv activity.log.tmp activity.log'
10 0 * * * cd /home/tc/selkouutiset-archive && flock /tmp/selkouutiset-archive-update.lock sh -c 'tail -n 1000 activity.log > activity.log.tmp && mv activity.log.tmp activity.log'
```

There are no separate `git pull` lines for the cleaned and archive checkouts:
the scripts sync themselves under their locks, and an unlocked pull could
change files under a running script. (The standalone
`/home/tc/selkouutiset-scrape` checkout is read only by the boot status
report.) Log trims take the same lock so they never cut a log a run is
writing to.
