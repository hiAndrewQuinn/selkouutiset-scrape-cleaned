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

fd '.*.fi.md$' | python translation-code/markdown2json.py
```

```fish
# Only if you have ☁️ Google Translate API and gcloud
curl -X POST \
          -H "Authorization: Bearer $(gcloud auth print-access-token)" \
          -H "x-goog-user-project: andrews-selkouutiset-archive" \
          -H "Content-Type: application/json; charset=utf-8" \
          -d @2023/11/11/_request.fi.en.json \
          "https://translation.googleapis.com/language/translate/v2"

fish translation-code/generate-translations.fish
fd '_response\...\...\.json' | python translation-code/json2markdown.py
```

## For end users: How things are named

The bulk of this Git repo is contained in the `YYYY/MM/DD` folders. Each `YYYY/MM/DD` folder contains 2*n things, where n is the number of languages we are translating to (curently just Finnish and English).

- `_index.source.md` is the Selkouutiset article, converted to Markdown, and translated into the appropriate language if necessary.
  - `source` is the langauge the article is in, as defined by the [ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes) standard.
  - `2023/10/25/_index.fi.md` is the Finnish-language version of the Selkouutiset articles from 2023.10.25.
  - `2023/11/11/_index.en.md` is the English-language version of the Selkouutiset articles from 2023.11.11.
- `_request.source.target.json` is a JSON file, generated from `_index.source.md` by a Python script, which contains the JSON request we send to the Google Translation API.
  - `source` should match `jq '.source'` for the JSON file.
  - `target` should match `'.target'`.
  - As an example, this file would be called `_index.fi.en.md`:
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
  - As an example, this file would be called `_index.fi.en.md`:
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

⚠️: `_index.source.md` doesn't actually clue you in as to _which_ translation was used to generate it. For this simple project that's not a big deal, because I'm not interested in running my JSON requests through `fi` then `ar` then `es` then `fr` then `en` just to mangle `_index.en.md` up. But if you're doing something more complicated, you might want to keep track of this.

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

again while in the root of the `cleaned` repo, to run all of our HTML files through the `pandoc` and `sed` filters that eventually produce our nice and clean `_index.fi.md` files.

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
fd '.*.fi.md$' | python translation-code/markdown2json.py
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
