#!/usr/bin/env python3
import typer
import json
import os
import sys
import re

app = typer.Typer()


def process_json(json_data: dict):
    return [item["translatedText"] for item in json_data["data"]["translations"]]


def get_language_code(json_file_path: str):
    return os.path.basename(json_file_path).split(".")[2]


def fix_image_links(content: str):
    """Fix image links in the translated content.

    For some reason, Google Translate adds spaces in random places in the URLs
    we use to link to YLE's images. Luckily, since the images are always on
    their own lines, this is easy to fix: Just remove all of the spaces
    inside ()s.
    """
    print("Analyzing line:")
    print(content)
    print("---")
    md_img_pattern = re.compile(r"!\[.*?\]\((.*?)\)")

    def remove_spaces_in_url(match):
        # Remove spaces in the URL part of the Markdown image syntax
        return f"![]({match.group(1).replace(' ', '')})"

    return (
        md_img_pattern.sub(remove_spaces_in_url, content)
        if md_img_pattern.search(content)
        else content
    )


def process_json_file(json_file_path: str):
    # The language code is in the file name: _request.source.target.json.
    # We want to take out target and use that as our language code.

    basedir = os.path.dirname(json_file_path)
    language_code = get_language_code(json_file_path)
    md_file_path = f"{basedir}/_index.{language_code}.md"
    typer.echo(f"{json_file_path} => {md_file_path}")

    with open(json_file_path, "r", encoding="utf-8") as file:
        data = process_json(json.load(file))

    # Fix any broken image links before we start processing the JSON.
    data = [fix_image_links(line) for line in data]
    content = "\n".join(data)

    # Write the content to the new Markdown file
    with open(md_file_path, "w", encoding="utf-8") as file:
        file.write(content)

    typer.echo(f"{md_file_path} created.")


@app.command()
def process_files(files: list[str] = typer.Argument(None)):
    typer.echo(files)
    if not files:
        # Read from stdin if no arguments are provided
        files = [line.strip() for line in sys.stdin]

    for json_file_path in files:
        if os.path.isfile(json_file_path):
            process_json_file(json_file_path)
        else:
            typer.echo(f"File not found: {json_file_path}", err=True)


if __name__ == "__main__":
    app()
