#!/bin/sh

# Script to update submodules and process HTML files to Markdown,
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
for cmd in git pandoc perl seq printf date basename hostname sha1sum awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [ "$cmd" = "hostname" ]; then
            log_message "WARNING: 'hostname' command not found. Using fallback '$HOSTNAME'."
        elif [ "$cmd" = "sha1sum" ] || [ "$cmd" = "awk" ]; then
            log_message "ERROR: Required command '$cmd' for hash checking not found. Please install it."
            exit 1
        else
            log_message "ERROR: Required command '$cmd' not found. Please install it and ensure it's in your PATH."
            exit 1
        fi
    fi
done
log_message "All essential commands found or handled."

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

# --- 2. Process HTML to Markdown with .hash checking ---
log_message "Starting HTML to Markdown processing with .hash integrity checks..."

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
            
            source_html_file="${day_dir_candidate}/selkouutiset_${year_val}_${month_val}_${day_val}.html"
            target_base_dir="${year_val}/${month_val}/${day_val}"
            target_md_file="${target_base_dir}/index.en.md"
            processed_day_log_suffix="Day: $year_val/$month_val/$day_val, Source: '$source_html_file', Target: '$target_md_file'"

            if [ ! -f "$source_html_file" ]; then
                log_message "Skipped: Source HTML file not found. $processed_day_log_suffix"
                continue
            fi

            current_md5=$(sha1sum "$source_html_file" | awk '{print $1}')
            if [ -z "$current_md5" ]; then
                log_message "ERROR: Failed to calculate MD5 for source. Skipping. $processed_day_log_suffix"
                continue
            fi

            stored_hash_line=$(grep -F -- "$source_html_file" "$HASH_FILE" || true)
            generate_md=false # Flag to control pandoc pipeline execution

            if [ -z "$stored_hash_line" ]; then
                # Rule 1: HTML file not in .hash
                printf "%s %s\n" "$source_html_file" "$current_md5" >> "$HASH_FILE"
                if [ ! -f "$target_md_file" ]; then
                    log_message "File newly added to '$HASH_FILE' (MD5: '$current_md5'). Target MD missing, will generate. $processed_day_log_suffix"
                    generate_md=true
                else
                    log_message "File newly added to '$HASH_FILE' (MD5: '$current_md5'). Target MD exists, generation skipped. $processed_day_log_suffix"
                fi
            else
                # File IS in .hash
                stored_md5=$(echo "$stored_hash_line" | awk '{print $2}')
                if [ -z "$stored_md5" ]; then
                    log_message "ERROR: Could not extract stored MD5 from line: '$stored_hash_line'. Skipping. $processed_day_log_suffix"
                    continue
                fi

                if [ "$current_md5" = "$stored_md5" ]; then
                    # Rule 2: Hashes match
                    if [ ! -f "$target_md_file" ]; then
                        log_message "Current MD5 '$current_md5' matches stored. Target MD missing, will generate. $processed_day_log_suffix"
                        generate_md=true
                    else
                        log_message "Current MD5 '$current_md5' matches stored. Target MD exists. MD generation skipped. $processed_day_log_suffix"
                    fi
                else
                    # Rule 3: Hashes DO NOT match - CRITICAL ERROR
                    log_message "CRITICAL HASH MISMATCH! Stored MD5: '$stored_md5', Current MD5: '$current_md5'. ABORTING SCRIPT. $processed_day_log_suffix"
                    exit 2 # Specific exit code for hash mismatch
                fi
            fi

            if [ "$generate_md" = true ]; then
                log_message "Proceeding with MD generation. $processed_day_log_suffix"
                if ! mkdir -p "$target_base_dir"; then
                    log_message "ERROR: Failed to create target directory '$target_base_dir'. Cannot generate MD. $processed_day_log_suffix"
                    continue 
                fi
            
                tmp_md_file="${target_md_file}.tmp.$$" 
                # No separate "Pipeline starting" log, included in "Proceeding with MD generation" or implied by success/failure logs.

                if cat "$source_html_file" | \
                   pandoc --from=html --to=commonmark --wrap=none | \
                   perl -pe 's{</?(?!img.*yle\.fi)[^>]*>}{}gi' | \
                   perl -0777 -pe 's/^(\s*\n)+//g' | \
                   perl -0777 -pe 's/(\s*\n)*(Tulosta|Jaa)(\s*\n(Tulosta|Jaa))*\s*$//' | \
                   perl -0777 -pe 's/\n{3,}/\n\n/g' | \
                   perl -0777 -pe 's/\s*$/\n/ if /./; $_ = "" if $_ eq "\n";' > "$tmp_md_file"; then
                    mv "$tmp_md_file" "$target_md_file"
                    log_message "Success: Created/Updated '$target_md_file'. $processed_day_log_suffix"
                else
                    log_message "Failed: Pipeline error during MD generation for '$target_md_file'. Temp file '$tmp_md_file' removed. $processed_day_log_suffix"
                    rm -f "$tmp_md_file" 
                    # set -e will cause the script to exit here.
                fi
            fi
        done # Day loop
    done # Month loop
done # Year loop

log_message "All source directories checked. Processing complete."
exit 0

