#!/usr/bin/env python3
import typer
import json
import os
import sys

# This humble Python script generates Google Cloud Translation API compatible
# JSON files from Markdown files. I find it works best by passing things
# recursively with `fd`: `fd '.*.md' | ./markdown2json.py`.

app = typer.Typer()


def process_markdown_file(md_file_path: str, target_lang: str = "en"):
    """
    Process a markdown file and create a corresponding JSON file for translation.

    Args:
    md_file_path (str): Path to the markdown file.
    target_lang (str): ISO 639-1 code for the target translation language. Defaults to 'en'.
    """
    # Derive the JSON file path from the markdown file path
    source_lang = os.path.split(md_file_path)[1].split(".")[1]
    typer.echo(f"Source language detected from filename: {source_lang}")
    json_file_path = (
        f"{os.path.split(md_file_path)[0]}/_request.{source_lang}.{target_lang}.json"
    )
    typer.echo("Creating: " + json_file_path)

    # Read the markdown file
    with open(md_file_path, "r", encoding="utf-8") as file:
        lines = file.readlines()

    # Strip whitespace from each line
    lines = [line.strip() for line in lines]

    # Create the JSON data for translation
    json_data = {"q": lines, "source": "fi", "target": target_lang, "format": "text"}

    # Write the JSON data to a file
    with open(json_file_path, "w", encoding="utf-8") as json_file:
        json.dump(json_data, json_file, indent=4, ensure_ascii=False)

    # Inform the user that the file has been created
    typer.echo(f"{json_file_path} file has been created.")


@app.command()
def process_files(files: list[str] = typer.Argument(None)):
    typer.echo(files)
    if not files:
        typer.echo("No files provided. Reading from stdin.")
        # Read from stdin if no arguments are provided
        files = [line.strip() for line in sys.stdin]

    for md_file_path in files:
        typer.echo("Processing: " + md_file_path)
        if os.path.isfile(md_file_path):
            process_markdown_file(md_file_path)
        else:
            typer.echo(f"File not found: {md_file_path}", err=True)


if __name__ == "__main__":
    app()