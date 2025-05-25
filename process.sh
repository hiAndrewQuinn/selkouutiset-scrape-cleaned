#!/bin/sh

# Script to update submodules, process HTML files to Finnish Markdown (index.fi.md),
# generate translation request JSON files, translate to English (index.en.md) via Google Translate API
# using gcloud for authentication (Perl for JSON parsing),
# caches API responses as _response.fi.en.json to avoid redundant calls,
# with .hash file checking for content integrity and regeneration control.
# Designed for POSIX sh (e.g., BusyBox ash on Tiny Core Linux).
# UTF-8 handling enhanced by setting LC_ALL and ensuring correct pipeline processing.
# Further refined Perl JSON generation to explicitly decode input and correctly output bytes.
# ADDED: --force flag to compel regeneration of markdown and JSON files.

# Exit immediately if a command exits with a non-zero status.
set -e

# Ensure a consistent UTF-8 environment for all commands
export LC_ALL=C.UTF-8
# Suppress Perl locale warnings by setting PERL_BADLANG to 0
export PERL_BADLANG=0

# --- Script Setup ---
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) # Absolute path to script's directory
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
  # Ensure multi-line messages are handled by indenting subsequent lines or processing line by line
  echo "$*" | while IFS= read -r line; do
    printf "%s %s %s[%d]: %s\n" "$timestamp" "$HOSTNAME" "$SCRIPT_NAME" "$$" "$line"
  done
}

# --- ADDED: Handle --force argument ---
force_regeneration=false
if [ "$1" = "--force" ]; then
  force_regeneration=true
  log_message "Force regeneration flag (--force) detected. Artifacts will be regenerated where possible."
  shift # Consume the --force argument so it doesn't interfere with other potential args (none currently)
fi

# --- Ensure $HOME/.local/bin is in PATH for cron ---
# This is to ensure tools like pandoc, installed in the user's local bin, are found
# when the script is run via cron, which often has a minimal PATH.
log_message "Checking and potentially updating PATH for user-specific binaries."
if [ -n "$HOME" ] && [ -d "$HOME/.local/bin" ]; then
  # Check if $HOME/.local/bin is already in PATH to avoid redundant additions
  # and overly long PATH variables, though functionally it's often not an issue.
  # The pattern matching ensures we match the exact path component.
  case ":$PATH:" in
  *":$HOME/.local/bin:"*)
    log_message "$HOME/.local/bin already in PATH."
    ;;
  *)
    export PATH="$HOME/.local/bin:$PATH"
    log_message "Prepended $HOME/.local/bin to PATH. New PATH: $PATH"
    ;;
  esac
else
  if [ -z "$HOME" ]; then
    log_message "Warning: HOME environment variable not set. Cannot reliably add user's .local/bin to PATH."
  else
    log_message "Note: Directory $HOME/.local/bin does not exist. Not added to PATH."
  fi
fi

# --- 0. Dependency Check ---
log_message "Checking for required commands..."
# Added curl, gcloud, sed.
for cmd in git pandoc perl seq printf date basename hostname sha1sum awk sort curl gcloud sed; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ "$cmd" = "hostname" ]; then
      log_message "WARNING: 'hostname' command not found. Using fallback '$HOSTNAME'."
    elif [ "$cmd" = "sha1sum" ] || [ "$cmd" = "awk" ] || [ "$cmd" = "sort" ]; then
      log_message "ERROR: Required command '$cmd' for hash/file operations not found. Please install it."
      exit 1
    elif [ "$cmd" = "curl" ] || [ "$cmd" = "gcloud" ] || [ "$cmd" = "sed" ]; then
      log_message "ERROR: Required command '$cmd' for API interaction or config not found. Please install it."
      exit 1
    else
      log_message "ERROR: Required command '$cmd' not found. Please install it and ensure it's in your PATH."
      exit 1
    fi
  fi
done

# Specifically check pandoc version
PANDOC_REQUIRED_VERSION="pandoc 3.7.0.1" # Matched to your script's value
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
  log_message "Perl module JSON::PP is available (used for request and response JSON)."
else
  log_message "ERROR: Perl module JSON::PP not found. This module is core in Perl since version 5.14."
  log_message "Your Perl version: $(perl -v | grep 'This is perl' || echo 'Perl version not detectable easily')"
  log_message "Please ensure your Perl installation is complete or install JSON::PP if using a very old/custom Perl."
  exit 1
fi

# --- Configuration Loading from .env file ---
ENV_FILE="$SCRIPT_DIR/.env"
GCP_PROJECT_ID="" # Initialize

log_message "Attempting to load configuration from '$ENV_FILE'..."
if [ -f "$ENV_FILE" ]; then
  # Load GCP_SELKOUUTISET_ARCHIVE_PROJECT (Mandatory)
  PROJECT_ID_LINE=$(grep '^GCP_SELKOUUTISET_ARCHIVE_PROJECT=' "$ENV_FILE" || true)
  if [ -n "$PROJECT_ID_LINE" ]; then
    PROJECT_ID_FROM_ENV=$(echo "$PROJECT_ID_LINE" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
    if [ -n "$PROJECT_ID_FROM_ENV" ]; then
      GCP_PROJECT_ID="$PROJECT_ID_FROM_ENV"
      log_message "Successfully loaded GCP_SELKOUUTISET_ARCHIVE_PROJECT ('$GCP_PROJECT_ID') from '$ENV_FILE'."
    else
      log_message "ERROR: '$ENV_FILE' found, but GCP_SELKOUUTISET_ARCHIVE_PROJECT is empty or malformed. This is required."
      exit 1
    fi
  else
    log_message "ERROR: '$ENV_FILE' found, but line starting with 'GCP_SELKOUUTISET_ARCHIVE_PROJECT=' is missing. This is required."
    exit 1
  fi
else
  log_message "ERROR: Configuration file '$ENV_FILE' not found. This file is required."
  log_message "Please create '$ENV_FILE' with:"
  log_message "GCP_SELKOUUTISET_ARCHIVE_PROJECT=\"your-gcp-project-id\""
  exit 1
fi

# --- Authenticate and Fetch Access Token using gcloud ---
ACCESS_TOKEN=""
log_message "Attempting to generate Google Cloud access token using 'gcloud auth print-access-token'..."

ACCESS_TOKEN_CMD_OUTPUT=$(gcloud auth print-access-token 2>/dev/null) # Suppress gcloud's own stderr for cleaner capture if successful
GCLOUD_EXIT_CODE=$?

if [ $GCLOUD_EXIT_CODE -ne 0 ]; then
  log_message "CRITICAL ERROR: 'gcloud auth print-access-token' failed with exit code $GCLOUD_EXIT_CODE."
  log_message "Ensure you are logged in with 'gcloud auth login' and 'gcloud init' has been run."
  exit 1
elif [ -z "$ACCESS_TOKEN_CMD_OUTPUT" ]; then
  log_message "CRITICAL ERROR: 'gcloud auth print-access-token' succeeded but produced no output."
  log_message "This might indicate an issue with your gcloud configuration or authentication state."
  exit 1
else
  ACCESS_TOKEN="$ACCESS_TOKEN_CMD_OUTPUT"
  log_message "Successfully generated Google Cloud access token."
fi

# --- Test Google Translate API Connectivity and Authentication ---
log_message "Performing a test translation to verify API connectivity and authentication..."
TEST_TRANSLATION_TEXT="Hello"
TEST_TRANSLATION_SOURCE_LANG="en"
TEST_TRANSLATION_TARGET_LANG="fi"

TEST_REQUEST_JSON_STRING=$(printf '{"q": ["%s"],"source": "%s","target": "%s","format": "text"}' \
  "$TEST_TRANSLATION_TEXT" \
  "$TEST_TRANSLATION_SOURCE_LANG" \
  "$TEST_TRANSLATION_TARGET_LANG")

# Temp file for the test API response
test_api_response_tmp_file="$SCRIPT_DIR/test_translate_api_response.$$.json"

log_message "Test API call: Translating '$TEST_TRANSLATION_TEXT' from '$TEST_TRANSLATION_SOURCE_LANG' to '$TEST_TRANSLATION_TARGET_LANG'."

if curl --silent --fail -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: $GCP_PROJECT_ID" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "$TEST_REQUEST_JSON_STRING" \
  "https://translation.googleapis.com/language/translate/v2" >"$test_api_response_tmp_file"; then

  # PERL_BADLANG=0 is set globally, so internal locale settings/suppressions might be redundant
  # but are kept for clarity or if PERL_BADLANG was not set for some reason.
  if perl - "$test_api_response_tmp_file" <<'PERL_VALIDATE_TEST_RESPONSE_EOF'; then
      use POSIX qw(setlocale LC_ALL);
      setlocale(LC_ALL, "C"); 
      use strict;
      use warnings;
      no warnings 'locale'; 
      use utf8;
      binmode STDERR, ":encoding(UTF-8)"; 
      use JSON::PP;

      my $response_file = $ARGV[0];
      my $json_text;

      eval {
          open my $fh_in, "<:encoding(UTF-8)", $response_file or die "Cannot open API response file '\''$response_file'\'': $!\n";
          local $/ = undef;
          $json_text = <$fh_in>;
          close $fh_in;
      };
      if ($@) { my $e = $@; chomp $e; print STDERR "Perl Error reading test API response file '$response_file': $e\n"; exit 1; }

      unless (defined $json_text && length $json_text) {
          print STDERR "Perl Error: Test API response file '$response_file' is empty or could not be read.\n";
          exit 1;
      }

      my $decoded_json;
      eval { $decoded_json = JSON::PP->new->decode($json_text); };
      if ($@) { my $e = $@; chomp $e; print STDERR "Perl Error decoding JSON from test API response: $e\n"; exit 1; }

      unless (defined $decoded_json) { print STDERR "Perl Error: Failed to decode JSON from test API response, result undefined.\n"; exit 1; }

      if (
          ref $decoded_json eq 'HASH' &&
          exists $decoded_json->{data} && ref $decoded_json->{data} eq 'HASH' &&
          exists $decoded_json->{data}->{translations} && ref $decoded_json->{data}->{translations} eq 'ARRAY' &&
          scalar @{$decoded_json->{data}->{translations}} > 0 &&
          exists $decoded_json->{data}->{translations}->[0]->{translatedText} &&
          defined $decoded_json->{data}->{translations}->[0]->{translatedText} &&
          length $decoded_json->{data}->{translations}->[0]->{translatedText} > 0
      ) {
          exit 0; # Success
      } else {
          print STDERR "Perl Error: Test API response JSON structure is invalid or 'translatedText' is missing/empty.\n";
          exit 1;
      }
PERL_VALIDATE_TEST_RESPONSE_EOF
    log_message "Test translation successful. API connectivity and authentication verified."
    rm -f "$test_api_response_tmp_file"
  else
    log_message "CRITICAL ERROR: Test translation API call response validation failed (Perl script error)."
    log_message "Perl script STDERR should have details. Response from API was saved to '$test_api_response_tmp_file' (if curl succeeded)."
    if [ -f "$test_api_response_tmp_file" ]; then
      log_message "Content of '$test_api_response_tmp_file':"
      while IFS= read -r log_line || [ -n "$log_line" ]; do log_message "  $log_line"; done <"$test_api_response_tmp_file"
    fi
    exit 1
  fi
else
  CURL_EXIT_CODE=$?
  log_message "CRITICAL ERROR: Test translation API call failed. curl exit code: $CURL_EXIT_CODE."
  log_message "Check network, token, API endpoint ($GCP_PROJECT_ID), or quotas. Response (if any) in '$test_api_response_tmp_file'."
  if [ -f "$test_api_response_tmp_file" ]; then
    if [ -s "$test_api_response_tmp_file" ]; then
      log_message "Content of '$test_api_response_tmp_file':"
      while IFS= read -r log_line || [ -n "$log_line" ]; do log_message "  $log_line"; done <"$test_api_response_tmp_file"
    else
      rm -f "$test_api_response_tmp_file" # Remove empty file
    fi
  fi
  exit 1
fi

log_message "All essential commands, versions, modules, configurations, and API authentication test successful."

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

# --- 2. Process HTML to Markdown, Generate Translation JSON, and Translate ---
log_message "Starting HTML processing, JSON generation, and Translation..."

HASH_FILE=".hash"
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

      # --- ADDED: Initialize iteration-specific flags ---
      fi_md_generated_this_iteration=false
      request_json_generated_this_iteration=false
      api_called_in_this_iteration=false

      source_html_file_relative="${day_dir_candidate}/selkouutiset_${year_val}_${month_val}_${day_val}.html"
      source_html_file_for_hash="./${source_html_file_relative}" # Path as stored in .hash
      source_html_file_for_ops="$source_html_file_relative"      # Path for operations

      target_base_dir="${year_val}/${month_val}/${day_val}"
      target_md_fi_file="${target_base_dir}/index.fi.md"
      processed_day_log_suffix="Day: $year_val/$month_val/$day_val, SrcHTML: '$source_html_file_for_ops'"

      if [ ! -f "$source_html_file_for_ops" ]; then
        log_message "Skipped MD: Source HTML file not found. $processed_day_log_suffix"
        continue
      fi

      current_sha1=$(sha1sum "$source_html_file_for_ops" | awk '{print $1}')
      if [ -z "$current_sha1" ]; then
        log_message "ERROR MD: Failed to calculate SHA1 for source. Skipping. $processed_day_log_suffix"
        continue
      fi

      # --- MODIFIED: Logic for index.fi.md generation decision ---
      stored_hash_line=$(grep -F -- "$source_html_file_for_hash" "$HASH_FILE" || true)
      generate_md=false
      reason_for_md_gen=""

      if [ "$force_regeneration" = true ]; then
        log_message "MD Gen Decision: --force specified. Will attempt to generate FI MD. $processed_day_log_suffix, TargetMD: '$target_md_fi_file'"
        generate_md=true
        reason_for_md_gen="--force used; "
      else
        if [ -z "$stored_hash_line" ]; then
          # New entry for .hash file
          # No need to write to HASH_FILE here yet, do it only if MD generation is attempted or would be skipped but file is new
          if [ ! -f "$target_md_fi_file" ]; then
            log_message "MD Gen Decision: File new to '$HASH_FILE' (SHA1: '$current_sha1'). Target FI MD missing, will generate. $processed_day_log_suffix, TargetMD: '$target_md_fi_file'"
            generate_md=true
            reason_for_md_gen="new hash entry and target FI.MD missing; "
          else
            log_message "MD Skip Decision: File new to '$HASH_FILE' (SHA1: '$current_sha1'). Target FI MD exists, generation normally skipped. $processed_day_log_suffix, TargetMD: '$target_md_fi_file'"
            # Add to hash file even if skipping generation for a new file, to track it
            printf "%s %s\n" "$source_html_file_for_hash" "$current_sha1" >>"$HASH_FILE"
          fi
        else
          stored_sha1=$(echo "$stored_hash_line" | awk '{print $2}')
          if [ -z "$stored_sha1" ]; then
            log_message "ERROR MD: Could not extract stored SHA1 from line: '$stored_hash_line'. Skipping. $processed_day_log_suffix"
            continue
          fi

          if [ "$current_sha1" = "$stored_sha1" ]; then
            if [ ! -f "$target_md_fi_file" ]; then
              log_message "MD Gen Decision: Current SHA1 '$current_sha1' matches stored. Target FI MD missing, will generate. $processed_day_log_suffix, TargetMD: '$target_md_fi_file'"
              generate_md=true
              reason_for_md_gen="hash matches and target FI.MD missing; "
            else
              log_message "MD Skip Decision: Current SHA1 '$current_sha1' matches stored. Target FI MD exists. MD generation skipped. $processed_day_log_suffix, TargetMD: '$target_md_fi_file'"
            fi
          else
            log_message "CRITICAL HASH MISMATCH! Stored SHA1: '$stored_sha1', Current SHA1: '$current_sha1'. ABORTING SCRIPT. $processed_day_log_suffix"
            # Consider if you want to update the hash here or just abort. Current script aborts.
            # If you wanted to update and regenerate:
            # log_message "Hash mismatch. Will update hash and regenerate FI MD."
            # generate_md=true
            # reason_for_md_gen="hash mismatch, will update and regenerate; "
            # sed -i -e "\#^${source_html_file_for_hash} \#d" "$HASH_FILE" # Remove old hash
            # printf "%s %s\n" "$source_html_file_for_hash" "$current_sha1" >>"$HASH_FILE" # Add new hash
            exit 2 # Current behavior is to abort on mismatch
          fi
        fi
      fi

      # If generate_md is true and it was a new file, ensure hash is written
      if [ "$generate_md" = true ] && [ -z "$stored_hash_line" ]; then
        printf "%s %s\n" "$source_html_file_for_hash" "$current_sha1" >>"$HASH_FILE"
        log_message "MD Gen: Added new entry to '$HASH_FILE' for '$source_html_file_for_hash' as part of generation."
      fi

      if [ "$generate_md" = true ]; then
        log_message "MD Gen: Proceeding with FI MD generation for '$target_md_fi_file'. Reason(s): $reason_for_md_gen $processed_day_log_suffix"
        if ! mkdir -p "$target_base_dir"; then
          log_message "ERROR MD: Failed to create target directory '$target_base_dir'. Cannot generate FI MD. $processed_day_log_suffix"
          continue
        fi

        tmp_md_file="${target_md_fi_file}.tmp.$$"
        if cat "$source_html_file_for_ops" |
          pandoc --from=html --to=commonmark --wrap=none |
          perl -CSDA -pe 's{src="data:image/svg\+xml;base64,[^"]*"}{}gi' |
          perl -CSDA -pe 's{<img\s+([^>]+)>}{ my $attrs_img = $1; my $src_img = ($attrs_img =~ m{src="([^"]*)"}i) ? $1 : undef; my $alt_img = ($attrs_img =~ m{alt="([^"]*)"}i) ? $1 : undef; (defined $src_img && defined $alt_img) ? sprintf("![%s](%s)", $alt_img, $src_img) : $& }gei' |
          perl -CSDA -pe 's{</?(?!img.*yle\.fi)[^>]*>}{}gi' |
          perl -CSDA -0777 -pe 's/^(\s*\n)+//g' |
          perl -CSDA -0777 -pe 's/(\s*\n)*(Tulosta|Jaa)(\s*\n(Tulosta|Jaa))*\s*$//' |
          perl -CSDA -0777 -pe 's/\n{3,}/\n\n/g' |
          perl -CSDA -0777 -pe 's/\s*$/\n/ if /./; $_ = "" if $_ eq "\n";' >"$tmp_md_file"; then
          mv "$tmp_md_file" "$target_md_fi_file"
          log_message "MD Success: Created/Updated '$target_md_fi_file'. $processed_day_log_suffix"
          fi_md_generated_this_iteration=true
        else
          log_message "MD Failed: Pipeline error during FI MD generation for '$target_md_fi_file'. Temp file '$tmp_md_file' removed. $processed_day_log_suffix"
          rm -f "$tmp_md_file"
          fi_md_generated_this_iteration=false
        fi
      fi

      # --- MODIFIED: Logic for _request.fi.en.json generation ---
      abs_target_md_fi_file="$PWD/$target_md_fi_file"
      target_request_json_file="${target_base_dir}/_request.fi.en.json"
      abs_target_request_json_file="$PWD/$target_request_json_file"
      generate_request_json=false
      reason_for_request_json_gen=""

      if [ -f "$target_md_fi_file" ]; then # Prerequisite: FI MD must exist
        json_gen_log_suffix="TargetRequestJSON: '$target_request_json_file', from FI MD: '$target_md_fi_file'"
        if [ "$force_regeneration" = true ]; then
          generate_request_json=true
          reason_for_request_json_gen="--force used; "
        elif [ "$fi_md_generated_this_iteration" = true ]; then
          generate_request_json=true
          reason_for_request_json_gen="FI.MD was just regenerated; "
        elif [ ! -f "$abs_target_request_json_file" ]; then
          generate_request_json=true
          reason_for_request_json_gen="Request JSON missing; "
        fi

        if [ "$generate_request_json" = true ]; then
          log_message "JSON Gen: Generating translation request JSON '$abs_target_request_json_file'. Reason(s): $reason_for_request_json_gen $json_gen_log_suffix"
          if perl - "$abs_target_md_fi_file" "$abs_target_request_json_file" <<'PERL_SCRIPT_EOF'; then
              use POSIX qw(setlocale LC_ALL);
              setlocale(LC_ALL, "C"); 
              use strict;
              use warnings;
              no warnings 'locale'; 
              use utf8; 
              binmode STDERR, ":encoding(UTF-8)"; 
              use JSON::PP;
              use Encode qw(decode FB_CROAK); 

              my $md_filepath = $ARGV[0];
              my $json_filepath = $ARGV[1];

              unless (defined $md_filepath && length $md_filepath && -f $md_filepath) {
                  die "Perl Error: Input MD file path invalid or file not found: RCV['\''$md_filepath'\'']\n";
              }
              unless (defined $json_filepath && length $json_filepath) {
                  die "Perl Error: Output JSON file path invalid: RCV['\''$json_filepath'\'']\n";
              }

              my @lines_for_json;
              open(my $fh_in, "<:raw", $md_filepath)
                  or die "Perl Error: Could not open MD file (raw) '\''$md_filepath'\'': $!\n";
              while (my $line_bytes = <$fh_in>) {
                  my $line_chars = Encode::decode('UTF-8', $line_bytes, FB_CROAK);
                  chomp $line_chars; 
                  push @lines_for_json, $line_chars;
              }
              close $fh_in;

              my $data_to_encode = {
                  q      => \@lines_for_json,
                  source => "fi",
                  target => "en",
                  format => "text",
              };

              my $json_encoder = JSON::PP->new->utf8(1)->pretty(1);
              my $json_byte_string = $json_encoder->encode($data_to_encode);

              open(my $fh_out, ">:raw", $json_filepath)
                  or die "Perl Error: Could not create JSON file (raw) '\''$json_filepath'\'': $!\n";
              print $fh_out $json_byte_string;
              close $fh_out;
PERL_SCRIPT_EOF
            log_message "JSON Success: Created translation request JSON. $json_gen_log_suffix"
            request_json_generated_this_iteration=true
          else
            log_message "JSON ERROR: Perl script (using JSON::PP) failed to generate request JSON. $json_gen_log_suffix"
            rm -f "$abs_target_request_json_file" # Remove partial/failed file
            request_json_generated_this_iteration=false
          fi
        else
          log_message "JSON Skip: Translation request JSON '$abs_target_request_json_file' exists, FI.MD not freshly generated, and --force not used. $json_gen_log_suffix"
        fi
      else
        log_message "JSON Skip: Cannot generate request JSON as source FI MD file '$target_md_fi_file' does not exist. $processed_day_log_suffix"
      fi

      # --- MODIFIED: Logic for _response.fi.en.json (API Call) and index.en.md generation ---
      target_response_json_file="${target_base_dir}/_response.fi.en.json"
      abs_target_response_json_file="$PWD/$target_response_json_file"
      target_en_md_file="${target_base_dir}/index.en.md"
      abs_target_en_md_file="$PWD/$target_en_md_file"

      if [ -f "$abs_target_request_json_file" ]; then
        translate_log_suffix="TargetEN_MD: '$target_en_md_file', from RequestJSON: '$abs_target_request_json_file'"

        # --- ADDED: Delete cached response if forcing or if request JSON was new ---
        if [ "$force_regeneration" = true ] && [ -f "$abs_target_response_json_file" ]; then
          log_message "TRANSLATE Force API: --force used, deleting existing response cache '$abs_target_response_json_file'."
          rm -f "$abs_target_response_json_file"
        elif [ "$request_json_generated_this_iteration" = true ] && [ -f "$abs_target_response_json_file" ]; then
          log_message "TRANSLATE Force API: Request JSON was regenerated, deleting existing response cache '$abs_target_response_json_file'."
          rm -f "$abs_target_response_json_file"
        fi

        if [ -f "$abs_target_response_json_file" ]; then
          log_message "TRANSLATE Skip API Call: Response file '$abs_target_response_json_file' already exists. Using cached response. $translate_log_suffix"
        else
          log_message "TRANSLATE API Call: Response file '$abs_target_response_json_file' not found (or removed for refresh). Calling API. $translate_log_suffix"
          if [ -z "$ACCESS_TOKEN" ]; then
            log_message "TRANSLATE ERROR: Access token not available (gcloud auth failed). Cannot call API. $translate_log_suffix"
            continue
          elif [ -z "$GCP_PROJECT_ID" ]; then
            log_message "TRANSLATE ERROR: GCP_PROJECT_ID is not set. Cannot call API. $translate_log_suffix"
            continue
          fi

          if curl --silent --fail -X POST \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "x-goog-user-project: $GCP_PROJECT_ID" \
            -H "Content-Type: application/json; charset=utf-8" \
            -d "@$abs_target_request_json_file" \
            "https://translation.googleapis.com/language/translate/v2" >"$abs_target_response_json_file"; then
            log_message "TRANSLATE API Success: API call successful, response saved to '$abs_target_response_json_file'. $translate_log_suffix"
            api_called_in_this_iteration=true
          else
            CURL_API_EXIT_CODE=$?
            log_message "TRANSLATE API ERROR: curl command failed with exit code $CURL_API_EXIT_CODE. $translate_log_suffix"
            if [ -s "$abs_target_response_json_file" ]; then # Check if file has content before logging
              log_message "Content of failed API response file '$abs_target_response_json_file':"
              while IFS= read -r log_line || [ -n "$log_line" ]; do log_message "  $log_line"; done <"$abs_target_response_json_file"
            fi
            rm -f "$abs_target_response_json_file" # Remove failed/partial response file
            log_message "TRANSLATE API ERROR: Removed failed/partial response file '$abs_target_response_json_file'. Skipping EN.MD generation for this item."
            continue # Skip to next item in the loop
          fi
        fi

        # --- MODIFIED: Conditional parsing of _response.fi.en.json to index.en.md ---
        # This block is reached if _response.fi.en.json exists (either cached or newly fetched)

        reason_for_en_md_gen=""
        generate_en_md=false

        if [ "$force_regeneration" = true ]; then
          generate_en_md=true
          reason_for_en_md_gen="--force used; "
        elif [ ! -f "$abs_target_en_md_file" ]; then
          generate_en_md=true
          reason_for_en_md_gen="EN.MD missing; "
        elif [ "$api_called_in_this_iteration" = true ]; then
          generate_en_md=true
          reason_for_en_md_gen="API freshly called (response updated); "
        fi

        if [ "$generate_en_md" = true ]; then
          if [ -f "$abs_target_response_json_file" ]; then # Ensure response file is still there
            log_message "TRANSLATE Parse: Generating '$abs_target_en_md_file' from '$abs_target_response_json_file'. Reason(s): $reason_for_en_md_gen $translate_log_suffix"
            if perl - "$abs_target_response_json_file" "$abs_target_en_md_file" <<'PERL_PARSE_RESPONSE_EOF'; then
                    use POSIX qw(setlocale LC_ALL);
                    setlocale(LC_ALL, "C"); 
                    use strict;
                    use warnings;
                    no warnings 'locale'; 
                    use utf8;
                    binmode STDERR, ":encoding(UTF-8)"; 
                    use JSON::PP;

                    if (@ARGV < 2) {
                        print STDERR "Perl Internal Error: Missing arguments (input_json_file, output_md_file).\n";
                        exit 2; 
                    }
                    my $input_json_file = $ARGV[0];
                    my $output_md_file = $ARGV[1];
                    my $json_text;

                    eval {
                        open my $fh_in, "<:encoding(UTF-8)", $input_json_file or die "Cannot open input file '\''$input_json_file'\'': $!\n";
                        local $/ = undef; 
                        $json_text = <$fh_in>;
                        close $fh_in;
                    };
                    if ($@) {
                        my $errmsg = $@; $errmsg =~ s/\n/ /g; 
                        print STDERR "Perl Error reading input file '$input_json_file' for parsing: $errmsg\n"; 
                        exit 1;
                    }
                    unless (defined $json_text && length $json_text) {
                        print STDERR "Perl Error: API response file '$input_json_file' is empty or could not be read.\n";
                        exit 1;
                    }

                    my $decoded_json;
                    eval { $decoded_json = JSON::PP->new->decode($json_text); };
                    if ($@) {
                        my $errmsg = $@; $errmsg =~ s/\n/ /g;
                        print STDERR "Perl Error decoding JSON from API response file '$input_json_file': $errmsg\n"; 
                        exit 1;
                    }
                    unless (defined $decoded_json) {
                        print STDERR "Perl Error: Failed to decode JSON from API response file '$input_json_file', result is undefined.\n";
                        exit 1;
                    }

                    unless (
                        ref $decoded_json eq 'HASH' &&
                        exists $decoded_json->{data} && ref $decoded_json->{data} eq 'HASH' &&
                        exists $decoded_json->{data}->{translations} && ref $decoded_json->{data}->{translations} eq 'ARRAY'
                    ) {
                        print STDERR "Perl Warning: Unexpected JSON structure in API response file '$input_json_file'. Expected 'data.translations' (array). File might contain an API error message.\n";
                        # Allow to proceed to output an empty file or handle error content if any
                    }

                    eval {
                        open my $fh_out, ">:encoding(UTF-8)", $output_md_file or die "Cannot open output file '\''$output_md_file'\'': $!\n";
                        if (ref $decoded_json eq 'HASH' && exists $decoded_json->{data} && ref $decoded_json->{data} eq 'HASH' &&
                            exists $decoded_json->{data}->{translations} && ref $decoded_json->{data}->{translations} eq 'ARRAY')
                        {
                            my @translations_arr = @{$decoded_json->{data}->{translations}};
                            foreach my $item (@translations_arr) {
                                if (ref $item eq 'HASH' && exists $item->{translatedText} && defined $item->{translatedText}) {
                                    print $fh_out $item->{translatedText} . "\n";
                                } else {
                                    print STDERR "Perl Warning: Malformed translation item (missing 'translatedText') in response file '$input_json_file'. Skipping item.\n";
                                }
                            }
                        } else {
                            # If structure is not as expected but an error object might be at top level:
                            if (ref $decoded_json eq 'HASH' && exists $decoded_json->{error} && ref $decoded_json->{error} eq 'HASH' && exists $decoded_json->{error}->{message}) {
                                print STDERR "Perl Note: API Error found in '$input_json_file': " . $decoded_json->{error}->{message} . ". Output MD '$output_md_file' will be empty.\n";
                            } else {
                                print STDERR "Perl Note: 'data.translations' array not found in expected structure in '$input_json_file'. Output MD file '$output_md_file' will be empty or reflect previous content if not overwritten.\n";
                            }
                        }
                        close $fh_out;
                    };
                    if ($@) {
                        my $errmsg = $@; $errmsg =~ s/\n/ /g;
                        print STDERR "Perl Error writing to output file '$output_md_file': $errmsg\n"; 
                        exit 1; 
                    }
                    exit 0; 
PERL_PARSE_RESPONSE_EOF
              log_message "TRANSLATE Parse Success: Processed '$abs_target_response_json_file' to '$abs_target_en_md_file'. $translate_log_suffix"
            else
              log_message "TRANSLATE Parse ERROR: Perl script failed to parse response file '$abs_target_response_json_file' or write to '$abs_target_en_md_file'. $translate_log_suffix"
              log_message "The response file '$abs_target_response_json_file' is kept for inspection. Perl STDERR should have details."
            fi
          else
            log_message "TRANSLATE Parse SKIPPED (Error): Response file '$abs_target_response_json_file' is unexpectedly missing, though regeneration was intended. $translate_log_suffix"
          fi
        else
          log_message "TRANSLATE Parse SKIPPED (No Change): Target EN MD '$abs_target_en_md_file' exists, its source response JSON '$abs_target_response_json_file' was cached (not freshly called via API), and --force not used. $translate_log_suffix"
        fi
      else
        log_message "TRANSLATE Skip: Request JSON file '$abs_target_request_json_file' not found. Cannot proceed with translation. $processed_day_log_suffix"
      fi

    done # day
  done   # month
done     # year

log_message "Sorting and uniquifying '$HASH_FILE'..."
if [ -s "$HASH_FILE" ]; then # Check if file exists and is not empty
  sort -u "$HASH_FILE" -o "$HASH_FILE"
  log_message "'$HASH_FILE' sorted."
else
  log_message "'$HASH_FILE' is empty or does not exist, no sorting needed."
fi

log_message "All source directories checked. Processing complete."
exit 0
