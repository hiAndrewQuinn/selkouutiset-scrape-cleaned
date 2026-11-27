# `selkoutiset-scrape-cleaned`

How do the raw HTML files in [selkouutiset-scrape](https://github.com/hiAndrewQuinn/selkouutiset-scrape) get cleaned up in to nice, easy-to-read Markdown files? This repository is how, using a combination of shell scripts and (as the needs of the project grew) Python as well.

Here I'm going to outline how to do all of these steps **by hand**. If you want to run the whole process, you can just run the shell script `run.sh` (which is what I do).

## Quickstart

```fish
# Safe to run over and over! Try it out!
cd /tmp && rm -rf selkouutiset-scrape-cleaned/ 

git clone https://github.com/hiAndrewQuinn/selkouutiset-scrape-cleaned.git
cd selkouutiset-scrape-cleaned

fish update.fish

rm .hash
rm -rf 2024/02  # does NOT work with all earlier versions out of the box sadly.
fish create-markdown-versions.fish

cat languages.txt | while read -l lang
    fd '.*.fi.md$' | python translation-code/markdown2json.py --target-lang=$lang
end
```

```fish
# ☁️ gcloud + Google Translate API ONLY, `curl` is to test.
set GCP_SELKOUUTISET_ARCHIVE_PROJECT 'andrews-selkouutiset-archive'
curl -X POST \
          -H "Authorization: Bearer $(gcloud auth print-access-token)" \
          -H "x-goog-user-project: $GCP_SELKOUUTISET_ARCHIVE_PROJECT" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d @2023/11/11/_request.fi.en.json \
          "https://translation.googleapis.com/language/translate/v2" | jq .

# Now we actually send the requests to the cloud.
fish translation-code/generate-translations.fish $GCP_SELKOUUTISET_ARCHIVE_PROJECT
fd '_response\...\...\.json' | python translation-code/json2markdown.py
```

## 2006–2009: pages from the old podcast feed

`2006/` to `2009/` are not made by `process.sh`, which works from Yle's HTML pages. They come from selkouutiset-scrape's `podcast-feed/`: the full text of 632 radio broadcasts (27.4.2006 – 5.2.2009) recovered from Wayback Machine snapshots of Yle's old podcast feed. `tools/podcast_feed_pages.py` writes them:

```sh
uv run tools/podcast_feed_pages.py selkouutiset-scrape/podcast-feed .
```

Each broadcast gets `index.fi.md` (heading `# Torstai 27.4.2006 (radio)`, then the text, with the feed's story separators as rules) and `edition.json` with a `"source"` naming the snapshot. The programme went out Sunday to Thursday. A Friday or Saturday straight after a broadcast gets a repeat page; any other day without one gets no page and is listed on the site as lost media. They are Finnish-only and never translated: they predate `TRANSLATE_FROM`, and the tool writes no translation request. The tool is idempotent and only ever rewrites days it wrote itself.

## For end users: How things are named

The bulk of this Git repo is contained in the `YYYY/MM/DD` folders. Each `YYYY/MM/DD` folder contains 2*n things, where n is the number of languages we are translating to (curently just Finnish and English).

- `index.source.md` is the Selkouutiset article, converted to Markdown, and translated into the appropriate language if necessary.
  - `source` is the langauge the article is in, as defined by the [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) standard.
  - `2023/10/25/index.fi.md` is the Finnish-language version of the Selkouutiset articles from 2023.10.25.
  - `2023/11/11/index.en.md` is the English-language version of the Selkouutiset articles from 2023.11.11.
- `_request.source.target.json` is a JSON file, generated from `index.source.md` by a Python script, which contains the JSON request we send to the Google Translation API.
  - `source` should match `jq '.source'` for the JSON file.
  - `target` should match `'.target'`.
  - As an example, this file would be called `index.fi.en.md`:
    ```json
    {
      "source": "fi",
      "target": "en",
      "q": [
        "Tämä on testi."
      ],
      "format": "text"
    }
    ```
- `_response.source.target.json` is a JSON file, which contains the JSON response we get back from sending `_request.source.target.json` to the Google Translation API.
  - `source` should match `jq '.source'` for the JSON file.
  - `target` should match `'.target'`.
  - As an example, this file would be called `index.fi.en.md`:
    ```json
    {
      "data": {
        "translations": [
          {
            "translatedText": "This is a test."
          }
        ]
      }
    }
    ```

- `edition.json` says which Yle edition the day's page actually holds:
  ```json
  {"edition": "2025-12-23", "article": "74-20201299"}
  ```
  - The upstream scrape keeps exactly one page per calendar day, holding the newest edition Yle published **on or before** that day. On days Yle published nothing new (Christmas, Easter, some weekends) the page therefore repeats an earlier edition: `2025/12/25/edition.json` says `"edition": "2025-12-23"`.
  - `edition` is Yle's own schema.org `datePublished` from the raw HTML (Helsinki time), the same date the scraper files by. The date printed in the headline is deliberately *not* used: Yle's headlines carry typos (`12.1.2023` on a 2024 edition, `28.5.20206`, a weekday a day off).
  - `article` is the edition's Yle article ID; the edition is online at `https://yle.fi/a/<article>`.
  - `"lost": true` is added when the day is listed in the scrape's [`lost.txt`](https://github.com/hiAndrewQuinn/selkouutiset-scrape/blob/main/lost.txt): Yle published an edition that day, but no copy survives anywhere, so the page holds the previous edition.
  - The archive website reads this file to label repeat days ("Yle published no new edition on this day…") and lost days ("(lost media)") rather than guessing from the text.

### What gets translated, and what it can cost

`process.sh` only pays Google for a translation when there is genuinely new Finnish text to translate, and it has hard limits on top of that.

**Spending guards** (environment variables, checked on every run and logged at the start and end):

| variable | default | effect |
|---|---|---|
| `TRANSLATE_FROM` | `20261124` | Days **before** this date are never sent to the API. Every day up to 2026-11-25 was already translated when the freeze was set; everything earlier that has no translation (the 2016-2023 history backfill, and days the scraper later repaired) stays Finnish-only, and the website marks it "(no English translation)". |
| `MAX_API_TRANSLATIONS` | `3` | Hard cap on paid API calls per run. A normal run needs 1-2 (today, plus yesterday when a late capture upgraded it). Anything over the cap is not sent (`TRANSLATE CAP` in the log) and is retried by a later run, so a mistake costs at most a few cents per run. |

Besides those calls, every run sends one 5-character connectivity test before doing anything else (a negligible cost).

**When a translation is reused, kept, or dropped:**

- **Re-captures of the same edition.** The scraper captures up to three times a day, and Yle's pages carry per-request bytes (build IDs, timestamps), so the HTML hash changes on nearly every capture. If the regenerated `index.fi.md` is byte-identical to the existing one, the translation is kept and nothing downstream is regenerated (`MD Unchanged` in the log).
- **Identical text anywhere.** When a day's `index.fi.md` is byte-identical to a day that already has a translation (the day before, for holiday repeats, or any other day, e.g. an edition the scraper once filed a day off), that `_response.fi.en.json` is copied instead of calling the API (`TRANSLATE Reused`). A two-week holiday stretch costs one translation, not fourteen. This applies before `TRANSLATE_FROM` too, since it is free.
- **Changed text.** A translation is thrown away only when the day's Finnish text really changed (`TRANSLATE Invalidate`); its `index.en.md` goes with it, so the site never shows English for a different edition. Then: identical text elsewhere is reused; else a day before `TRANSLATE_FROM` stays Finnish-only (`TRANSLATE Frozen`); else it is translated, within the cap.
- **`--force`** regenerates the Markdown and JSON, but no longer pays to re-translate unchanged text (it used to delete every response, which would have re-translated the whole archive).
- Request JSON is written with sorted keys, so regenerating identical content gives identical bytes and no spurious git diff.

To translate the backfill deliberately one day (about 2,600 days, roughly $130), lift both guards for one run, e.g. `TRANSLATE_FROM=20160901 MAX_API_TRANSLATIONS=3000 sh process.sh`. Nothing does this automatically.

⚠️: `index.source.md` doesn't actually clue you in as to _which_ translation was used to generate it. For this simple project that's not a big deal, because I'm not interested in running my JSON requests through `fi` then `ar` then `es` then `fr` then `en` just to mangle `index.en.md` up. But if you're doing something more complicated, you might want to keep track of this.

## Detailed instructions

### Update the submodules to the latest commit

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

again while in the root of the `cleaned` repo, to run all of our HTML files through the `pandoc` and `sed` filters that eventually produce our nice and clean `index.fi.md` files.

In an automated environment, I usually run `create-markdown-versions` and then immediately commit the changes:

```fish
git add -A
set timestamp (date -u)
git commit -m "Latest data: $timestamp" || exit 0
git push
```

Experience has taught me not to put this git commit code into `create-markdown-versions` itself. ;)

Like `update.sh`, this is also safe to run on a loop.

### ☁️ Create translations with the Google Translation API

Alright, *here's* where things get a bit tricky. We have a bunch of Finnish-language Markdown files, but we want to create English-language versions of them (or Spanish-, or Farsi-, or what have you). As a former cloud guy, I like working with any of the Big Three, and in this case I decided to go with Google. *So*, in order to do the translations yourself, you need to have **a Google Cloud account** and **a Google Cloud project** with the **Google Translation API** enabled. [Here are the API docs](https://cloud.google.com/translate/docs/) if that sounds fun to you.

#### Generate JSON request

There are two Python files in `translation-code/`: `markdown2json.py`, and `json2markdown.py`. The easiest way to use them is by piping in the names of the files you wish to transform with the `fd` command:

```fish
cat languages.txt | while read -l lang
    fd '.*.fi.md$' | python translation-code/markdown2json.py --target-lang=$lang
end
```

#### Send JSON requests to the cloud

For the purposes of testing whether your `gcloud` CLI is set up properly, you can run the following command:

```fish
curl -X POST \
          -H "Authorization: Bearer $(gcloud auth print-access-token)" \
          -H "x-goog-user-project: andrews-selkouutiset-archive" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d @2023/11/11/_request.fi.en.json \
          "https://translation.googleapis.com/language/translate/v2"
```

If you get back something that looks like JSON-wrapped translated text, you're in the clear! Run

```fish
fish translation-code/generate-translations.fish
```

to send all of the JSON requests to the cloud and save the responses. (This is also safe to run on a loop - if a e.g. `_request.fi.en.json` file already exists in that `YYYY/MM/DD` file, it won't be sent to the cloud again, and you won't be charged.)

### Process JSON responses into new Markdown files

The grand finale. Take all of those `_response`s you just generated and run them through our opposite, `json2markdown.py`.

```fish
fd '_response\...\...\.json' | python translation-code/json2markdown.py
```
