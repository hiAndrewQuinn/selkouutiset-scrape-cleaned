#!/usr/bin/env python3
import typer
import json
import os
import sys

app = typer.Typer()


def process_json_file(json_file_path: str):
    with open(json_file_path, "r", encoding="utf-8") as file:
        data = json.load(file)

    language_code = data["source"]
    # Determine the new file name
    base_name = os.path.splitext(json_file_path)[0]
    print(base_name)

    md_file_path = f"{base_name}.{language_code}.md"

    # Extract the content from the "q" key
    content = "\n".join(data["q"])

    # Write the content to the new Markdown file
    with open(md_file_path, "w", encoding="utf-8") as file:
        file.write(content)

    typer.echo(f"{md_file_path} file has been created.")


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
