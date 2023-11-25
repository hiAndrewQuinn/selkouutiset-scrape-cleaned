#!/usr/bin/env python3
import typer
import json
import os
import sys

# This humble Python script generates Google Cloud Translation API compatible
# JSON files from Markdown files. I find it works best by passing things
# recursively with `fd`: `fd '.*.md' | ./markdown2json.py`.

app = typer.Typer()


def process_markdown_file(md_file_path: str):
    json_file_path = f"{os.path.splitext(md_file_path)[0]}.md.json"

    with open(md_file_path, "r", encoding="utf-8") as file:
        lines = file.readlines()

    lines = [line.strip() for line in lines]

    json_data = {"q": lines, "source": "fi", "target": "en", "format": "text"}

    with open(json_file_path, "w", encoding="utf-8") as json_file:
        json.dump(json_data, json_file, indent=4, ensure_ascii=False)

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
