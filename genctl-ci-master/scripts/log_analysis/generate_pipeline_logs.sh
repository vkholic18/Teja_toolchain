#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This script provides deterministic, AI-ready failure analysis for IBM
# OnePipeline (Tekton) CI runs. It scans pipeline_logs, removes debug noise,
# and detects ALL independent failures across default tasks and custom jobs.
#
# Key Capabilities:
# - Extracts task_name and step_name from embedded metadata
#   (### PIPELINE_INFO_FOR_LOG_ANALYSIS) when available
# - Falls back safely to folder/file names if metadata is absent
# - Detects multiple failure types:
#     • Custom job failures (e.g., "Finished job ... with failure")
#     • Exit Code failures (Exit Code != 0)
#     • Evidence table failures (Status = failure)
# - Anchors logs at the LAST real failure point (root-cause focused)
# - Adds contextual lines around failure (before + after anchor)
# - Constructs precise step-level IBM Cloud URLs for direct navigation
# - Generates structured, AI-optimized failed-logs.txt for BOB analysis
# - Enforces output size control (16MB guard)
# - Supports parallel processing for large pipeline logs
#
# Outcome:
# Reduces manual triage time, improves root-cause accuracy,
# and accelerates CI incident resolution across shared environments.
# ----------------------------------------------------------------------------------------------


############################################
# CONFIG
############################################

MAX_OUTPUT_SIZE=$((16 * 1024 * 1024))  # 16MB
PARALLEL_JOBS=4
FAILED_LOG="failed-logs.txt"
TEMP_DIR=".ai_log_tmp"
DEBUG_PATTERN="::debug::"

############################################
# VALIDATION
############################################

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <pipeline_logs_directory>"
  exit 1
fi

PIPELINE_DIR="$1"

if [[ ! -d "$PIPELINE_DIR" ]]; then
  echo "Directory not found: $PIPELINE_DIR"
  exit 1
fi

rm -rf "$TEMP_DIR" "$FAILED_LOG"
mkdir -p "$TEMP_DIR"

############################################
# GET BASE HTML URL
############################################

METADATA_FILE="$PIPELINE_DIR/metadata.json"
BASE_HTML_URL=""

if [[ -f "$METADATA_FILE" ]]; then
  BASE_HTML_URL=$(grep -o '"html_url":[[:space:]]*"[^"]*"' "$METADATA_FILE" \
    | sed 's/.*"html_url":[[:space:]]*"\([^"]*\)".*/\1/')
fi

############################################
# UTIL: Cross-platform file size
############################################

get_file_size() {
  if stat --version >/dev/null 2>&1; then
    stat -c %s "$1"
  else
    stat -f %z "$1"
  fi
}

############################################
# CLEAN DEBUG LINES
############################################

clean_debug_lines() {
  local file="$1"
  grep -v "$DEBUG_PATTERN" "$file" > "${file}.clean"
  mv "${file}.clean" "$file"
}

############################################
# FAILURE DETECTION
############################################

is_failure_file() {
  local file="$1"

  ############################################
  #Custom job failures (strong signal)
  ############################################
  if grep -qE "Exiting .* with failure|Finished job .* with failure" "$file"; then
    return 0
  fi

  ############################################
  #Evidence table failure (strong signal)
  ############################################
  if grep -qE "│ Status[[:space:]]*│[[:space:]]*failure" "$file"; then
    return 0
  fi

  ############################################
  #Check final stage exit status
  ############################################
  local final_exit
  final_exit=$(grep -E "Execution of custom script for stage .* Exit Code:" "$file" \
                | tail -1 | sed -E "s/.*Exit Code: '([0-9]+)'.*/\1/" || true)

  if [[ -n "$final_exit" ]]; then
    if [[ "$final_exit" -ne 0 ]]; then
      return 0
    else
      # Explicit success — do NOT treat as failure
      return 1
    fi
  fi

  ############################################
  #Non-zero exit inside task (not stage)
  ############################################
  if grep -qE "Exit Code: '[1-9][0-9]*'" "$file"; then
    return 0
  fi

  ############################################
  #Strong crash patterns only
  ############################################
  if grep -qiE "Traceback \(most recent call last\)|Segmentation fault|panic:|Unhandled Exception" "$file"; then
    return 0
  fi

  return 1
}

############################################
# SMART TRUNCATION (ROOT-CAUSE FIRST)
############################################
smart_truncate_log() {
  local file="$1"
  local total_lines
  total_lines=$(wc -l < "$file")

  local anchors=()

  ############################################
  # Collect all strong failure anchors
  ############################################

  # Evidence failures
  while IFS=: read -r line _; do
    anchors+=("$line:evidence")
  done < <(grep -n "│ Status" "$file" | grep -i failure || true)

  # Custom job failures
  while IFS=: read -r line _; do
    anchors+=("$line:custom")
  done < <(grep -nE "Exiting .* with failure|Finished job .* with failure" "$file" || true)

  # Non-zero exit (exclude stage summary)
  while IFS=: read -r line _; do
    anchors+=("$line:exit")
  done < <(grep -nE "Exit Code: '[1-9][0-9]*'" "$file" \
            | grep -v "Execution of custom script for stage" || true)

  # Stage summary exit
  while IFS=: read -r line _; do
    anchors+=("$line:stage")
  done < <(grep -nE "Execution of custom script for stage .* Exit Code: '[1-9][0-9]*'" "$file" || true)

  ############################################
  # If no anchors → fallback
  ############################################
  if [[ ${#anchors[@]} -eq 0 ]]; then
    return
  fi

  ############################################
  # Sort and deduplicate nearby anchors
  ############################################
  IFS=$'\n' sorted=($(printf "%s\n" "${anchors[@]}" | sort -n -t: -k1))
  unset IFS

  local last_printed_line=0

  for entry in "${sorted[@]}"; do
    local anchor_line="${entry%%:*}"
    local anchor_type="${entry##*:}"

    # Skip anchors too close to previous (within 50 lines)
    if (( anchor_line - last_printed_line < 50 )); then
      continue
    fi

    last_printed_line="$anchor_line"

    local start_line=$((anchor_line - 200))
    if [[ $start_line -lt 1 ]]; then
      start_line=1
    fi

    local end_line="$anchor_line"

    # If evidence → include 15 lines after
    if [[ "$anchor_type" == "evidence" ]]; then
      end_line=$((anchor_line + 15))
      if [[ $end_line -gt $total_lines ]]; then
        end_line=$total_lines
      fi
    fi

    echo "----- FAILURE OCCURRENCE -----"
    sed -n "${start_line},${end_line}p" "$file"
    echo ""
  done
}


############################################
# PROCESS SINGLE FILE
############################################

process_file() {
  local file="$1"
  local folder
  folder=$(basename "$(dirname "$file")")
  local filename
  filename=$(basename "$file")

  case "$filename" in
    dind.log|tekton-log-results.log|prepare.log|prepare-next-stage.log)
      return
      ;;
  esac

  clean_debug_lines "$file"

  if is_failure_file "$file"; then

    local task_name="$folder"
    local step_name="${filename%.*}"
    # ------------------------------------------
    # Resolve logical task & step names
    # ------------------------------------------

    real_task_name=""
    real_step_name=""

    # Try extracting from PIPELINE_INFO_FOR_LOG_ANALYSIS
    pattern_line=$(grep -m1 "PIPELINE_INFO_FOR_LOG_ANALYSIS" "$file")

    if [[ -n "$pattern_line" ]]; then
        real_task_name=$(echo "$pattern_line" | sed -n "s/.*task_name=\([^|]*\).*/\1/p" | xargs)
        real_step_name=$(echo "$pattern_line" | sed -n "s/.*step_name=\([^|]*\).*/\1/p" | xargs)
    fi

    # Fallback to folder/file if pattern missing or empty
    if [[ -z "$real_task_name" ]]; then
        real_task_name="$folder"
    fi

    if [[ -z "$real_step_name" ]]; then
        real_step_name="$filename"
    fi

    local step_url=""

    if [[ -n "$BASE_HTML_URL" ]]; then

        # Split base URL into path and query
        local base_path="${BASE_HTML_URL%%\?*}"
        local query_part=""
        
        if [[ "$BASE_HTML_URL" == *\?* ]]; then
            query_part="${BASE_HTML_URL#*\?}"
        fi

        # Construct proper step-level URL
        if [[ -n "$query_part" ]]; then
            step_url="${base_path}/${folder}/${step_name}?${query_part}&view=logs"
        else
            step_url="${base_path}/${folder}/${step_name}?view=logs"
        fi
    fi

    {
      echo "########## FAILURE BLOCK ##########"
      echo "TASK_NAME: $real_task_name"
      echo "STEP_NAME: $real_step_name"
      echo "STEP_URL: $step_url"
      echo "------------------------------------"
      smart_truncate_log "$file"
      echo ""
    } > "$TEMP_DIR/${folder}_${filename}.fail"
  fi
}

export -f process_file
export -f clean_debug_lines
export -f is_failure_file
export -f smart_truncate_log
export DEBUG_PATTERN BASE_HTML_URL TEMP_DIR

############################################
# PARALLEL PROCESSING
############################################

find "$PIPELINE_DIR/logs" -type f | \
  xargs -I {} -P "$PARALLEL_JOBS" bash -c 'process_file "$@"' _ {}

############################################
# AGGREGATE OUTPUT
############################################

if compgen -G "$TEMP_DIR/*.fail" > /dev/null; then

  {
    echo "========================================="
    echo "PIPELINE FAILURE REPORT"
    echo "Generated: $(date -u)"
    echo "========================================="
    echo ""
  } > "$FAILED_LOG"

  cat "$TEMP_DIR"/*.fail >> "$FAILED_LOG"

  FILE_SIZE=$(get_file_size "$FAILED_LOG")

  if [[ "$FILE_SIZE" -gt "$MAX_OUTPUT_SIZE" ]]; then
    echo "⚠ Output exceeded 16MB. Truncating..."
    head -c "$MAX_OUTPUT_SIZE" "$FAILED_LOG" > "${FAILED_LOG}.tmp"
    mv "${FAILED_LOG}.tmp" "$FAILED_LOG"
  fi

  echo "Failed log file generated: $FAILED_LOG"

else
  echo "No failures detected. No failed-logs.txt created."
fi

rm -rf "$TEMP_DIR"
