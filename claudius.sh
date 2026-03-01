#!/usr/bin/env bash
# Claudius v0.5.1 - Claude Code + LM Studio bootstrapper (named for the fourth Roman emperor).
# Author: Lefteris Iliadis (Somnius) https://github.com/Somnius
# Check server, pick model, set context length, update config, run claude.
# Requires: LM Studio (local server on port 1234); jq or Python for JSON; Claude Code CLI.

set -euo pipefail

VERSION="0.5.1"
LMSTUDIO_URL="${LMSTUDIO_URL:-http://localhost:1234}"
LMSTUDIO_API="${LMSTUDIO_URL}/api/v1"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CLAUDIUS_PREFS="${HOME}/.claude/claudius-prefs.json"
CLAUDE_HOME="${HOME}/.claude"
BASHRC="${HOME}/.bashrc"

# Session-related paths under ~/.claude to purge (do not include settings.json or claudius-prefs.json)
SESSION_DIRS="projects debug file-history tasks todos plans shell-snapshots session-env paste-cache"

# Curl timeout: connect + max total (avoid hanging)
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

# --- First-time / --init: ask preferences and save to CLAUDIUS_PREFS ---
run_init() {
  echo "Claudius first-time setup (preferences saved to $CLAUDIUS_PREFS)"
  echo ""

  local show_turn="y"
  read -rp "Show reply duration after each response (e.g. 'Cooked for 1m 6s')? [Y/n]: " show_turn
  show_turn="${show_turn:-y}"
  local show_turn_bool=true
  [[ "${show_turn,,}" == "n" || "${show_turn,,}" == "no" ]] && show_turn_bool=false

  local keep_sess="y"
  read -rp "Keep session history when Claude Code exits? [Y/n]: " keep_sess
  keep_sess="${keep_sess:-y}"
  local keep_sess_bool=true
  [[ "${keep_sess,,}" == "n" || "${keep_sess,,}" == "no" ]] && keep_sess_bool=false

  mkdir -p "$(dirname "$CLAUDIUS_PREFS")"
  if command -v jq &>/dev/null; then
    jq -n \
      --arg st "$show_turn_bool" --arg ks "$keep_sess_bool" \
      '{showTurnDuration: ($st == "true"), keepSessionOnExit: ($ks == "true")}' > "$CLAUDIUS_PREFS"
  else
    printf '%s\n' "{\"showTurnDuration\": $show_turn_bool, \"keepSessionOnExit\": $keep_sess_bool}" > "$CLAUDIUS_PREFS"
  fi
  echo "  Saved. Run claudius --init again anytime to change these."
  echo ""
}

# --- Read showTurnDuration from prefs; default true ---
get_show_turn_duration() {
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    echo "true"
    return
  fi
  if command -v jq &>/dev/null; then
    jq -r '.showTurnDuration // true | tostring' "$CLAUDIUS_PREFS" 2>/dev/null || echo "true"
  else
    python3 -c "import json; print(json.load(open('$CLAUDIUS_PREFS')).get('showTurnDuration', True))" 2>/dev/null || echo "true"
  fi
}

# --- Read keepSessionOnExit from prefs; default true ---
get_keep_session_on_exit() {
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    echo "true"
    return
  fi
  if command -v jq &>/dev/null; then
    jq -r '.keepSessionOnExit // true | tostring' "$CLAUDIUS_PREFS" 2>/dev/null || echo "true"
  else
    python3 -c "import json; print(json.load(open('$CLAUDIUS_PREFS')).get('keepSessionOnExit', True))" 2>/dev/null || echo "true"
  fi
}

# --- Purge session data: delete files in SESSION_DIRS and optionally history.jsonl ---
# Usage: purge_session_dirs [optional: also_clear_history 1]
# If also_clear_history=1, truncate/remove history.jsonl.
purge_session_dirs() {
  local also_history="${1:-0}"
  local d
  for d in $SESSION_DIRS; do
    [[ -d "${CLAUDE_HOME}/${d}" ]] && rm -rf "${CLAUDE_HOME}/${d}"/*
  done
  if [[ "$also_history" == "1" ]] && [[ -f "${CLAUDE_HOME}/history.jsonl" ]]; then
    : > "${CLAUDE_HOME}/history.jsonl"
  fi
}

# --- Purge session files older than N minutes (mtime < now - N min) ---
purge_older_than_mins() {
  local mins="$1"
  [[ -z "$mins" || ! "$mins" =~ ^[0-9]+$ ]] && return 1
  local d
  for d in $SESSION_DIRS; do
    [[ -d "${CLAUDE_HOME}/${d}" ]] || continue
    find "${CLAUDE_HOME}/${d}" -type f -mmin "+${mins}" -delete 2>/dev/null || true
    find "${CLAUDE_HOME}/${d}" -type d -empty -delete 2>/dev/null || true
  done
  # history.jsonl: remove lines with timestamp older than N min (timestamp is ms)
  if [[ -f "${CLAUDE_HOME}/history.jsonl" ]]; then
    local cutoff_ms
    cutoff_ms=$(($(date +%s) * 1000 - mins * 60 * 1000))
    if command -v jq &>/dev/null; then
      jq -c --argjson c "$cutoff_ms" 'select(.timestamp >= $c)' "${CLAUDE_HOME}/history.jsonl" 2>/dev/null > "${CLAUDE_HOME}/history.jsonl.tmp" && mv "${CLAUDE_HOME}/history.jsonl.tmp" "${CLAUDE_HOME}/history.jsonl"
    else
      python3 -c "
import sys, json
cutoff = $cutoff_ms
with open('${CLAUDE_HOME}/history.jsonl') as f:
    lines = [l for l in f if l.strip() and json.loads(l).get('timestamp', 0) >= cutoff]
with open('${CLAUDE_HOME}/history.jsonl', 'w') as f:
    f.writelines(lines)
" 2>/dev/null || true
    fi
  fi
}

# --- Purge session files from yesterday and back (mtime before today 00:00) ---
purge_yesterday_and_back() {
  local now_sec today_start_sec mins
  now_sec=$(date +%s)
  today_start_sec=$(python3 -c "from datetime import datetime; d=datetime.now().replace(hour=0,minute=0,second=0,microsecond=0); print(int(d.timestamp()))" 2>/dev/null) || today_start_sec=0
  mins=$(( (now_sec - today_start_sec) / 60 ))
  [[ "$mins" -lt 1 ]] && mins=1
  purge_older_than_mins "$mins"
}

# --- Purge recent session (last 2 min) - used after exit when keepSessionOnExit=false ---
purge_session_recent() {
  # Delete files modified in the last 2 minutes (current session)
  local d
  for d in $SESSION_DIRS; do
    [[ -d "${CLAUDE_HOME}/${d}" ]] || continue
    find "${CLAUDE_HOME}/${d}" -type f -mmin -2 -delete 2>/dev/null || true
    find "${CLAUDE_HOME}/${d}" -type d -empty -delete 2>/dev/null || true
  done
}

# --- --purge: interactive menu, then run chosen purge ---
run_purge() {
  echo "Claudius — purge saved session data under $CLAUDE_HOME"
  echo ""
  echo "  1) Purge ALL session data (2 verification questions)"
  echo "  2) Purge all from yesterday and back"
  echo "  3) Purge all from 6 hours and back"
  echo "  4) Purge all from 3 hours and back"
  echo "  5) Purge all from 2 hours and back"
  echo "  6) Purge all from 1 hour and back"
  echo "  7) Purge all from 30 minutes and back"
  echo "  q) Cancel"
  echo ""

  local choice
  read -rp "Choose (1-7 or q): " choice
  case "$choice" in
    q|Q) echo "Cancelled."; return 0 ;;
    1)
      read -rp "Type YES to confirm purge of ALL session data: " a
      [[ "${a^^}" != "YES" ]] && echo "Cancelled." && return 0
      read -rp "Type PURGE to confirm again: " b
      [[ "${b^^}" != "PURGE" ]] && echo "Cancelled." && return 0
      purge_session_dirs 1
      echo "  Purged all session data."
      ;;
    2) purge_yesterday_and_back; echo "  Purged session data from yesterday and back." ;;
    3) purge_older_than_mins 360; echo "  Purged session data older than 6 hours." ;;
    4) purge_older_than_mins 180; echo "  Purged session data older than 3 hours." ;;
    5) purge_older_than_mins 120; echo "  Purged session data older than 2 hours." ;;
    6) purge_older_than_mins 60;  echo "  Purged session data older than 1 hour." ;;
    7) purge_older_than_mins 30;  echo "  Purged session data older than 30 minutes." ;;
    *) echo "Invalid choice."; return 1 ;;
  esac
  return 0
}

# --- After session (when keepSessionOnExit=false): menu to delete current session or purge by age ---
run_after_session_menu() {
  echo "Session ended. Delete session data?"
  echo ""
  echo "  1) Delete current session only (last ~2 min)"
  echo "  2) Purge ALL session data (2 verification questions)"
  echo "  3) Purge all from yesterday and back"
  echo "  4) Purge all from 6 hours and back"
  echo "  5) Purge all from 3 hours and back"
  echo "  6) Purge all from 2 hours and back"
  echo "  7) Purge all from 1 hour and back"
  echo "  8) Purge all from 30 minutes and back"
  echo "  9) Skip (keep everything)"
  echo ""

  local choice
  read -rp "Choose (1-9): " choice
  case "$choice" in
    1) purge_session_recent; echo "  Deleted current session." ;;
    2)
      read -rp "Type YES to confirm purge of ALL session data: " a
      [[ "${a^^}" != "YES" ]] && echo "Skipped." && return 0
      read -rp "Type PURGE to confirm again: " b
      [[ "${b^^}" != "PURGE" ]] && echo "Skipped." && return 0
      purge_session_dirs 1
      echo "  Purged all session data."
      ;;
    3) purge_yesterday_and_back; echo "  Purged session data from yesterday and back." ;;
    4) purge_older_than_mins 360; echo "  Purged session data older than 6 hours." ;;
    5) purge_older_than_mins 180; echo "  Purged session data older than 3 hours." ;;
    6) purge_older_than_mins 120; echo "  Purged session data older than 2 hours." ;;
    7) purge_older_than_mins 60;  echo "  Purged session data older than 1 hour." ;;
    8) purge_older_than_mins 30;  echo "  Purged session data older than 30 minutes." ;;
    9) echo "  Skipped." ;;
    *) echo "  Skipped." ;;
  esac
  return 0
}

# --- Check if LM Studio server is reachable ---
check_server() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${LMSTUDIO_API}/models" 2>/dev/null) || true
  [[ "$code" == "200" ]]
}

# --- Prompt when server is not running: Resume / Try start / Abort ---
wait_for_server() {
  echo "LM Studio server is not running at ${LMSTUDIO_URL}."
  echo ""
  echo "  1) Resume  - I've started the server; check again."
  echo "  2) Start   - Try to start the server (runs: lms server start)."
  echo "  3) Abort   - Exit."
  echo ""

  local choice
  while true; do
    read -rp "Choose (1-3): " choice
    case "$choice" in
      1)
        if check_server; then
          echo "Server is up. Continuing."
          return 0
        fi
        echo "Still not reachable. Start the server in LM Studio (Local Inference Server), then choose Resume again."
        echo ""
        ;;
      2)
        if command -v lms &>/dev/null; then
          echo "Starting LM Studio server in background (lms server start)..."
          lms server start &
          sleep 3
          if check_server; then
            echo "Server is up. Continuing."
            return 0
          fi
          echo "Server may still be starting. Choose Resume to retry or Abort."
        else
          echo "Command 'lms' not found. Install LM Studio and ensure 'lms' is on your PATH (e.g. ~/.lmstudio/bin)."
          echo "Start the server from the LM Studio GUI, then choose Resume."
        fi
        echo ""
        ;;
      3)
        echo "Aborted."
        exit 1
        ;;
      *)
        echo "Invalid choice. Enter 1, 2, or 3."
        echo ""
        ;;
    esac
  done
}

# --- Fetch model list from LM Studio (native API: key and max_context_length) ---
# Output: one line per LLM: "key|max_context_length"
fetch_models() {
  local resp
  resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${LMSTUDIO_API}/models" 2>/dev/null) || true
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach LM Studio at ${LMSTUDIO_URL}. Is the local server running?" >&2
    return 1
  fi
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.models[]?' &>/dev/null; then
      echo "$resp" | jq -r '.models[] | select(.type == "llm") | "\(.key)|\(.max_context_length // 32768)"'
      return 0
    fi
  else
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('models', []):
        if m.get('type') == 'llm':
            print(m.get('key', '') + '|' + str(m.get('max_context_length', 32768)))
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse model list from LM Studio. Response: ${resp:0:200}" >&2
  return 1
}

# --- Interactive model selection (numbered menu); outputs "key|max_context_length" ---
select_model() {
  local keys=() max_ctx=()
  local line key ctx
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%|*}"
    ctx="${line##*|}"
    [[ -n "$key" ]] && keys+=("$key") && max_ctx+=("$ctx")
  done < <(fetch_models)

  if [[ ${#keys[@]} -eq 0 ]]; then
    echo "No models found. Start LM Studio and load a model, then try again." >&2
    return 1
  fi

  echo "Models available in LM Studio:" >&2
  echo "" >&2
  local i
  for i in "${!keys[@]}"; do
    printf "  %2d) %s (max %s tokens)\n" "$((i + 1))" "${keys[$i]}" "${max_ctx[$i]}" >&2
  done
  echo "  q) Quit" >&2
  echo "" >&2

  local choice num
  while true; do
    read -rp "Select model (1-${#keys[@]} or q): " choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      num=$((choice))
      if (( num >= 1 && num <= ${#keys[@]} )); then
        echo "${keys[$((num - 1))]}|${max_ctx[$((num - 1))]}"
        return 0
      fi
    fi
    echo "Invalid choice. Try again." >&2
  done
}

# --- Choose context length: 5 suggested values from min to max + custom ---
# Args: model_key, max_context_length. Outputs chosen context_length (number).
select_context_length() {
  local model_key="$1" max_ctx="$2"
  local min_ctx=2048
  [[ "$max_ctx" -lt "$min_ctx" ]] && min_ctx=1024
  if [[ "$max_ctx" -le "$min_ctx" ]]; then
    echo "$max_ctx"
    return 0
  fi

  # Five suggested values: spread from min_ctx to max_ctx (rounded to multiples of 256)
  local step=$(( (max_ctx - min_ctx) / 4 ))
  local v1=$min_ctx v2 v3 v4 v5=$max_ctx
  v2=$(( (min_ctx + step) / 256 * 256 ))
  v3=$(( (min_ctx + 2 * step) / 256 * 256 ))
  v4=$(( (min_ctx + 3 * step) / 256 * 256 ))
  [[ "$v2" -lt "$min_ctx" ]] && v2=$min_ctx
  [[ "$v3" -gt "$max_ctx" ]] && v3=$max_ctx
  [[ "$v4" -gt "$max_ctx" ]] && v4=$max_ctx

  echo "Context length (tokens) for $model_key: min $min_ctx, max $max_ctx" >&2
  echo "" >&2
  echo "  1) $v1" >&2
  echo "  2) $v2" >&2
  echo "  3) $v3" >&2
  echo "  4) $v4" >&2
  echo "  5) $max_ctx" >&2
  echo "  6) Custom (enter your own number)" >&2
  echo "" >&2

  local choice
  while true; do
    read -rp "Choose (1-6): " choice
    case "$choice" in
      1) echo "$v1"; return 0 ;;
      2) echo "$v2"; return 0 ;;
      3) echo "$v3"; return 0 ;;
      4) echo "$v4"; return 0 ;;
      5) echo "$max_ctx"; return 0 ;;
      6)
        read -rp "Enter context length (${min_ctx}-${max_ctx}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge "$min_ctx" ]] && [[ "$choice" -le "$max_ctx" ]]; then
          echo "$choice"
          return 0
        fi
        echo "Enter a number between $min_ctx and $max_ctx." >&2
        ;;
      *)
        echo "Invalid choice. Enter 1-6." >&2
        ;;
    esac
  done
}

# --- Spinner while a background job runs; first arg is PID, optional second is message ---
wait_with_spinner() {
  local pid="$1" msg="${2:-Loading...}"
  local spin='-\|/' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s  " "$msg" "${spin:i++%4:1}"
    sleep 0.15
  done
  printf "\r  %s done.   \n" "$msg"
}

# --- Load model with given context length via LM Studio API; show spinner until load finishes ---
load_model_with_context() {
  local model_key="$1" context_length="$2"
  local tmp resp body code
  tmp=$(mktemp)
  (
    curl -s -w "\n%{http_code}" --connect-timeout 2 --max-time 300 \
      -X POST -H "Content-Type: application/json" \
      -d "{\"model\": \"${model_key}\", \"context_length\": ${context_length}}" \
      "${LMSTUDIO_API}/models/load" 2>/dev/null || printf '\n000\n'
  ) > "$tmp" &
  wait_with_spinner $! "Loading model (context ${context_length})…"
  resp=$(cat "$tmp")
  rm -f "$tmp"
  body="${resp%$'\n'*}"
  code="${resp##*$'\n'}"
  if [[ "$code" != "200" ]]; then
    echo "Warning: LM Studio load returned HTTP $code. Response: ${body:0:200}" >&2
    return 1
  fi
  # Optionally show load time if present in JSON
  if command -v jq &>/dev/null && echo "$body" | jq -e '.load_time_seconds' &>/dev/null; then
    local secs
    secs=$(echo "$body" | jq -r '.load_time_seconds')
    echo "  Loaded $model_key with context length $context_length (${secs}s)."
  else
    echo "  Loaded $model_key with context length $context_length."
  fi
  return 0
}

# --- Update ~/.claude/settings.json ---
write_settings() {
  local model_id="$1"
  local show_turn
  show_turn=$(get_show_turn_duration)
  local schema="https://json.schemastore.org/claude-code-settings.json"
  local base_url="http://localhost:1234"
  local tmp
  tmp=$(mktemp)
  if command -v jq &>/dev/null; then
    jq -n \
      --arg schema "$schema" \
      --arg base "$base_url" \
      --arg model "$model_id" \
      --arg show_turn "$show_turn" \
      '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_AUTH_TOKEN": "lmstudio", "ANTHROPIC_API_KEY": ""}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
      > "$tmp"
  else
    python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_AUTH_TOKEN\": \"lmstudio\",
        \"ANTHROPIC_API_KEY\": \"\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
  fi
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  mv "$tmp" "$CLAUDE_SETTINGS"
  echo "  Updated: $CLAUDE_SETTINGS (defaultModel = $model_id)"
}

# --- Ensure .bashrc exports are set ---
update_bashrc() {
  local base_url="http://localhost:1234"
  local marker="# local Claude Code → LM Studio direct (Anthropic-compatible API)"
  local block="export ANTHROPIC_BASE_URL=${base_url}
export ANTHROPIC_AUTH_TOKEN=lmstudio
export ANTHROPIC_API_KEY=
export CLAUDE_CODE_ATTRIBUTION_HEADER=0"

  if grep -q "ANTHROPIC_BASE_URL" "$BASHRC" 2>/dev/null; then
    if grep -q "$marker" "$BASHRC" 2>/dev/null; then
      echo "  .bashrc already contains ANTHROPIC exports."
      return 0
    fi
  fi
  echo "" >> "$BASHRC"
  echo "$marker" >> "$BASHRC"
  echo "$block" >> "$BASHRC"
  echo "  Appended Claude Code env block to: $BASHRC"
}

# --- Verify config and env ---
verify_and_export() {
  local model_id="$1"
  export ANTHROPIC_BASE_URL="http://localhost:1234"
  export ANTHROPIC_AUTH_TOKEN="lmstudio"
  export ANTHROPIC_API_KEY=""
  export CLAUDE_CODE_ATTRIBUTION_HEADER="0"

  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "Warning: $CLAUDE_SETTINGS not found after write." >&2
    return 1
  fi
  local saved_model
  if command -v jq &>/dev/null; then
    saved_model=$(jq -r '.defaultModel // empty' "$CLAUDE_SETTINGS")
  else
    saved_model=$(python3 -c "import json; print(json.load(open('$CLAUDE_SETTINGS')).get('defaultModel',''))" 2>/dev/null)
  fi
  if [[ "$saved_model" != "$model_id" ]]; then
    echo "Warning: defaultModel in settings ($saved_model) != selected ($model_id). Using selected." >&2
  fi

  echo ""
  echo "Verified:"
  echo "  ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
  echo "  defaultModel (for this run)= $model_id"
  echo ""
}

# --- Main ---
main() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" || "${1:-}" == "--test" ]] && dry_run=1 && shift

  # --purge: interactive purge menu, then exit
  if [[ "${1:-}" == "--purge" ]]; then
    run_purge
    exit 0
  fi

  # --init: (re)run first-time setup questions and save preferences
  if [[ "${1:-}" == "--init" ]]; then
    run_init
    shift
  fi
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    run_init
  fi

  echo "Claudius v${VERSION} - Claude Code + LM Studio (direct)"
  echo "LM Studio URL: $LMSTUDIO_URL"
  [[ "$dry_run" -eq 1 ]] && echo "(dry-run: will not write config or start claude)"
  echo ""

  until check_server; do
    wait_for_server
  done

  local model_line model_id max_ctx
  model_line=$(select_model) || exit 1
  model_id="${model_line%%|*}"
  max_ctx="${model_line##*|}"
  echo ""
  echo "Selected: $model_id (max $max_ctx tokens)"
  echo ""

  local context_length
  context_length=$(select_context_length "$model_id" "$max_ctx") || exit 1
  echo ""
  echo "Context length: $context_length"
  echo ""

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] Would load $model_id with context $context_length, write $CLAUDE_SETTINGS, run: claude --model $model_id"
    exit 0
  fi

  echo "Loading model in LM Studio..."
  if ! load_model_with_context "$model_id" "$context_length"; then
    echo ""
    echo "Model load failed. Check LM Studio server logs for details (e.g. out of memory, missing file)."
    echo "Fix the issue and run claudius again, or choose another model/context length."
    exit 1
  fi

  echo "Writing config..."
  write_settings "$model_id"
  update_bashrc
  verify_and_export "$model_id"

  echo "Starting Claude Code..."
  echo ""

  local keep_sess
  keep_sess=$(get_keep_session_on_exit)
  if [[ "$keep_sess" == "true" ]]; then
    exec claude --model "$model_id"
  else
    claude --model "$model_id" || true
    echo ""
    run_after_session_menu
  fi
}

main "$@"
