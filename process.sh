#!/bin/sh

# Script to update submodules, process HTML files to Finnish Markdown (index.fi.md),
# generate translation request JSON files (with correct UTF-8 encoding),
# with .hash file checking for content integrity and regeneration control.
# Designed for POSIX sh (e.g., BusyBox ash on Tiny Core Linux).

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Script Setup ---
SCRIPT_NAME=$(basename "$0")
# Try to get hostname, default to 'script_host' if command not found or fails.
HOSTNAME_CMD_OUTPUT=$(hostname 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$HOSTNAME_CMD_OUTPUT" ]; then
  HOSTNAME="$HOSTNAME_CMD_OUTPUT"
else
  HOSTNAME="script_host" # Fallback hostname
fi

# Logging function for syslog-style messages
log_message() {
  timestamp=$(date +"%b %e %T")
  printf "%s %s %s[%d]: %s\n" "$timestamp" "$HOSTNAME" "$SCRIPT_NAME" "$$" "$*"
}

# --- 0. Dependency Check ---
log_message "Checking for required commands..."
for cmd in git pandoc perl seq printf date basename hostname sha1sum awk sort; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ "$cmd" = "hostname" ]; then
      log_message "WARNING: 'hostname' command not found. Using fallback '$HOSTNAME'."
    elif [ "$cmd" = "sha1sum" ] || [ "$cmd" = "awk" ] || [ "$cmd" = "sort" ]; then
      log_message "ERROR: Required command '$cmd' for hash/file operations not found. Please install it."
      exit 1
    else
      log_message "ERROR: Required command '$cmd' not found. Please install it and ensure it's in your PATH."
      exit 1
    fi
  fi
done

# Specifically check pandoc version
PANDOC_REQUIRED_VERSION="pandoc 3.7.0.1"
log_message "Checking pandoc version..."
pandoc_version_output=$(pandoc --version 2>/dev/null | head -n 1) # Get first line

if [ "$pandoc_version_output" = "$PANDOC_REQUIRED_VERSION" ]; then
  log_message "Pandoc version is correct: $pandoc_version_output"
else
  log_message "ERROR: Incorrect pandoc version. Found: '$pandoc_version_output'. Required: '$PANDOC_REQUIRED_VERSION'. Please install the correct version."
  exit 1
fi

# Check for Perl module JSON::PP (core in Perl 5.14+)
log_message "Checking for Perl module JSON::PP..."
if perl -MJSON::PP -e 1 >/dev/null 2>&1; then
  log_message "Perl module JSON::PP is available."
else
  # This case is highly unlikely with Perl 5.14+
  log_message "ERROR: Perl module JSON::PP not found. This module is core in Perl since version 5.14."
  log_message "Your Perl version: $(perl -v | grep 'This is perl' || echo 'Perl version not detectable easily')"
  log_message "Please ensure your Perl installation is complete or install JSON::PP if using a very old/custom Perl."
  exit 1
fi

log_message "All essential commands, versions, and modules found or handled."

# --- 1. Update Git Submodules ---
SUBMODULE_PATH="selkouutiset-scrape"
log_message "Updating Git submodule '$SUBMODULE_PATH'..."
git submodule update --init --remote --merge "$SUBMODULE_PATH"

log_message "Checking for submodule updates to commit..."
if git status --porcelain "$SUBMODULE_PATH" | grep -q "$SUBMODULE_PATH"; then
  log_message "Submodule '$SUBMODULE_PATH' has new commits. Staging and committing..."
  git add "$SUBMODULE_PATH"
  COMMIT_MSG="Update submodule $SUBMODULE_PATH to latest - $(date +'%Y-%m-%d %H:%M:%S')"
  git commit -m "$COMMIT_MSG"
  log_message "Committed submodule update: $COMMIT_MSG"
else
  log_message "Submodule '$SUBMODULE_PATH' is already up-to-date. No changes to commit in the parent repository."
fi

# --- 2. Process HTML to Markdown & Generate Translation JSON ---
log_message "Starting HTML to Markdown processing (for index.fi.md) and Translation JSON generation..."

HASH_FILE=".hash"
# Ensure .hash file exists
if [ ! -f "$HASH_FILE" ]; then
  log_message "Hash file '$HASH_FILE' not found, creating it."
  touch "$HASH_FILE"
fi

for year_dir_candidate in "$SUBMODULE_PATH"/20[0-9][0-9]; do
  if [ ! -d "$year_dir_candidate" ]; then continue; fi
  year_val=$(basename "$year_dir_candidate")

  for month_dir_candidate in "$year_dir_candidate"/[0-1][0-9]; do
    if [ ! -d "$month_dir_candidate" ]; then continue; fi
    month_val=$(basename "$month_dir_candidate")

    for day_dir_candidate in "$month_dir_candidate"/[0-3][0-9]; do
      if [ ! -d "$day_dir_candidate" ]; then continue; fi
      day_val=$(basename "$day_dir_candidate")

      source_html_file_relative="${day_dir_candidate}/selkouutiset_${year_val}_${month_val}_${day_val}.html"
      source_html_file_for_hash="./${source_html_file_relative}" # Path for .hash file will be prefixed with ./
      source_html_file_for_ops="$source_html_file_relative"      # Actual path for file operations

      target_base_dir="${year_val}/${month_val}/${day_val}"
      target_md_file="${target_base_dir}/index.fi.md"
      # Consistent log suffix for operations related to this day's article
      processed_day_log_suffix="Day: $year_val/$month_val/$day_val, Source HTML: '$source_html_file_for_ops', Target MD: '$target_md_file'"

      if [ ! -f "$source_html_file_for_ops" ]; then
        log_message "Skipped MD: Source HTML file not found. $processed_day_log_suffix"
        continue
      fi

      current_sha1=$(sha1sum "$source_html_file_for_ops" | awk '{print $1}')
      if [ -z "$current_sha1" ]; then
        log_message "ERROR MD: Failed to calculate SHA1 for source. Skipping. $processed_day_log_suffix"
        continue
      fi

      stored_hash_line=$(grep -F -- "$source_html_file_for_hash" "$HASH_FILE" || true)
      generate_md=false # Flag to control pandoc pipeline execution

      if [ -z "$stored_hash_line" ]; then
        # Rule 1: HTML file not in .hash
        printf "%s %s\n" "$source_html_file_for_hash" "$current_sha1" >>"$HASH_FILE"
        if [ ! -f "$target_md_file" ]; then
          log_message "MD Gen: File newly added to '$HASH_FILE' (SHA1: '$current_sha1'). Target MD missing, will generate. $processed_day_log_suffix"
          generate_md=true
        else
          log_message "MD Skip: File newly added to '$HASH_FILE' (SHA1: '$current_sha1'). Target MD exists, generation skipped. $processed_day_log_suffix"
        fi
      else
        # File IS in .hash
        stored_sha1=$(echo "$stored_hash_line" | awk '{print $2}')
        if [ -z "$stored_sha1" ]; then
          log_message "ERROR MD: Could not extract stored SHA1 from line: '$stored_hash_line'. Skipping. $processed_day_log_suffix"
          continue
        fi

        if [ "$current_sha1" = "$stored_sha1" ]; then
          # Rule 2: Hashes match
          if [ ! -f "$target_md_file" ]; then
            log_message "MD Gen: Current SHA1 '$current_sha1' matches stored. Target MD missing, will generate. $processed_day_log_suffix"
            generate_md=true
          else
            log_message "MD Skip: Current SHA1 '$current_sha1' matches stored. Target MD exists. MD generation skipped. $processed_day_log_suffix"
          fi
        else
          # Rule 3: Hashes DO NOT match - CRITICAL ERROR
          log_message "CRITICAL HASH MISMATCH! Stored SHA1: '$stored_sha1', Current SHA1: '$current_sha1'. ABORTING SCRIPT. $processed_day_log_suffix"
          exit 2 # Specific exit code for hash mismatch
        fi
      fi

      if [ "$generate_md" = true ]; then
        log_message "MD Gen: Proceeding with MD generation for '$target_md_file'. $processed_day_log_suffix"
        if ! mkdir -p "$target_base_dir"; then
          log_message "ERROR MD: Failed to create target directory '$target_base_dir'. Cannot generate MD. $processed_day_log_suffix"
          continue
        fi

        tmp_md_file="${target_md_file}.tmp.$$"
        if cat "$source_html_file_for_ops" |
          pandoc --from=html --to=commonmark --wrap=none |
          perl -pe 's{</?(?!img.*yle\.fi)[^>]*>}{}gi' |
          perl -0777 -pe 's/^(\s*\n)+//g' |
          perl -0777 -pe 's/(\s*\n)*(Tulosta|Jaa)(\s*\n(Tulosta|Jaa))*\s*$//' |
          perl -0777 -pe 's/\n{3,}/\n\n/g' |
          perl -0777 -pe 's/\s*$/\n/ if /./; $_ = "" if $_ eq "\n";' >"$tmp_md_file"; then
          mv "$tmp_md_file" "$target_md_file"
          log_message "MD Success: Created/Updated '$target_md_file'. $processed_day_log_suffix"
        else
          log_message "MD Failed: Pipeline error during MD generation for '$target_md_file'. Temp file '$tmp_md_file' removed. $processed_day_log_suffix"
          rm -f "$tmp_md_file"
          # set -e will cause the script to exit here.
        fi
      fi # End of "if generate_md is true"

      # --- Generate Translation Request JSON ---
      if [ -f "$target_md_file" ]; then
        target_json_file="${target_base_dir}/_request.fi.en.json"
        abs_target_md_file="$PWD/$target_md_file"
        abs_target_json_file="$PWD/$target_json_file"

        json_gen_log_suffix="Target JSON: '$target_json_file', from MD: '$target_md_file'"

        log_message "JSON Check: Checking/Creating translation request JSON. $json_gen_log_suffix"

        if [ -f "$abs_target_json_file" ]; then
          log_message "JSON Skip: Translation request JSON already exists. $json_gen_log_suffix"
        else
          log_message "JSON Gen: Generating translation request JSON (using JSON::PP, UTF-8 enforced)... $json_gen_log_suffix"
          if perl - "$abs_target_md_file" "$abs_target_json_file" <<'PERL_SCRIPT_EOF'; then
              use strict;
              use warnings;
              use utf8;         # Declare that this script (and strings) use UTF-8
              use JSON::PP;

              my $md_filepath = $ARGV[0];
              my $json_filepath = $ARGV[1];

              unless (defined $md_filepath && length $md_filepath && -f $md_filepath) {
                  die "Perl Error: Input MD file path invalid or file not found: RCV['\''$md_filepath'\'']\n";
              }
              unless (defined $json_filepath && length $json_filepath) {
                  die "Perl Error: Output JSON file path invalid: RCV['\''$json_filepath'\'']\n";
              }

              my @lines_for_json;
              # Open input MD file with UTF-8 encoding layer
              open(my $fh_in, "<:encoding(UTF-8)", $md_filepath)
                  or die "Perl Error: Could not open MD file '\''$md_filepath'\'': $!\n";
              while (my $line = <$fh_in>) {
                  chomp $line;
                  $line =~ s/^\s+|\s+$//g; # Strip leading/trailing whitespace
                  # $line is now a UTF-8 decoded Perl string
                  push @lines_for_json, $line;
              }
              close $fh_in;

              my $data_to_encode = {
                  q      => \@lines_for_json,
                  source => "fi",
                  target => "en",
                  format => "text",
              };

              # JSON::PP->utf8(1) ensures $json_string contains UTF-8 *bytes*
              my $json_encoder = JSON::PP->new->utf8(1)->pretty(1);
              my $json_string = $json_encoder->encode($data_to_encode);

              # Open output JSON file for writing raw bytes
              open(my $fh_out, ">", $json_filepath)
                  or die "Perl Error: Could not create JSON file '\''$json_filepath'\'': $!\n";
              binmode $fh_out; # Ensure filehandle is in binary mode (no CRLF translation, no encoding layers)
              print $fh_out $json_string; # Print the UTF-8 bytes directly
              close $fh_out;
PERL_SCRIPT_EOF
            log_message "JSON Success: Created translation request JSON. $json_gen_log_suffix"
          else
            log_message "JSON ERROR: Perl script (using JSON::PP) failed to generate JSON. $json_gen_log_suffix"
            rm -f "$abs_target_json_file"
          fi
        fi
      else
        log_message "JSON Skip: Skipping translation JSON generation as target MD file '$target_md_file' does not exist. $processed_day_log_suffix"
      fi

    done # Day loop
  done   # Month loop
done     # Year loop

log_message "Sorting and uniquifying '$HASH_FILE'..."
if [ -s "$HASH_FILE" ]; then
  sort -u "$HASH_FILE" -o "$HASH_FILE"
  log_message "'$HASH_FILE' sorted."
else
  log_message "'$HASH_FILE' is empty or does not exist, no sorting needed."
fi

log_message "All source directories checked. Processing complete for index.fi.md and _request.fi.en.json files."
exit 0

