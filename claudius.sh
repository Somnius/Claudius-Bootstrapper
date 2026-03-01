#!/usr/bin/env bash
# Claudius v0.3.1 - Claude Code + LM Studio bootstrapper (named for the fourth Roman emperor).
# Author: Lefteris Iliadis (Somnius) https://github.com/Somnius
# Check server, pick model, update config, run claude.
# Requires: LM Studio (local server on port 1234); jq or Python for JSON; Claude Code CLI.
# Optional: fzf or gum for interactive model selection.

set -euo pipefail

VERSION="0.3.1"
LMSTUDIO_URL="${LMSTUDIO_URL:-http://localhost:1234}"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
BASHRC="${HOME}/.bashrc"

# --- Check if LM Studio server is reachable ---
check_server() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "${LMSTUDIO_URL}/v1/models" 2>/dev/null) || true
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
        echo "Still not reachable. Start the server in LM Studio (Local Inference Server), then choose 1 again."
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
          echo "Server may still be starting. Choose 1 to retry or 3 to abort."
        else
          echo "Command 'lms' not found. Install LM Studio and ensure 'lms' is on your PATH (e.g. ~/.lmstudio/bin)."
          echo "Start the server from the LM Studio GUI, then choose 1 to resume."
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

# --- Fetch model list from LM Studio ---
fetch_models() {
  local resp
  resp=$(curl -s --connect-timeout 2 "${LMSTUDIO_URL}/v1/models" 2>/dev/null) || true
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach LM Studio at ${LMSTUDIO_URL}. Is the local server running?" >&2
    return 1
  fi
  # OpenAI-style: {"data":[{"id":"qwen/..."}],...} or LM Studio may use different shape
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.data[]?.id' &>/dev/null; then
      echo "$resp" | jq -r '.data[].id'
      return 0
    fi
    # Fallback: try .data[].id or .models[].key / .models[].id
    if echo "$resp" | jq -e '.models[]?' &>/dev/null; then
      echo "$resp" | jq -r '.models[] | (.id // .key // .display_name // empty)' 2>/dev/null | head -100
      return 0
    fi
  else
    # No jq: use Python to parse
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'data' in d:
        for m in d['data']:
            print(m.get('id', m.get('key', '')))
    elif 'models' in d:
        for m in d['models']:
            print(m.get('id', m.get('key', m.get('display_name', ''))))
    else:
        sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse model list from LM Studio. Response: ${resp:0:200}" >&2
  return 1
}

# --- Interactive model selection (fzf, gum, or fallback) ---
select_model() {
  local models
  models=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && models+=("$line")
  done < <(fetch_models)

  if [[ ${#models[@]} -eq 0 ]]; then
    echo "No models found. Start LM Studio and load a model, then try again." >&2
    return 1
  fi

  local selected
  if command -v fzf &>/dev/null; then
    selected=$(printf '%s\n' "${models[@]}" | fzf --height=~50% --prompt="Model> " 2>/dev/null) || true
    if [[ -n "$selected" ]]; then
      echo "$selected"
      return 0
    fi
    return 1
  fi

  if command -v gum &>/dev/null; then
    selected=$(gum choose "${models[@]}" 2>/dev/null) || true
    if [[ -n "$selected" ]]; then
      echo "$selected"
      return 0
    fi
    return 1
  fi

  # Fallback: numbered menu (menu to stderr so it shows when stdout is captured)
  echo "Models available in LM Studio:" >&2
  echo "" >&2
  local i
  for i in "${!models[@]}"; do
    printf "  %2d) %s\n" "$((i + 1))" "${models[$i]}" >&2
  done
  echo "  q) Quit" >&2
  echo "" >&2

  local choice num
  while true; do
    read -rp "Select model (1-${#models[@]} or q): " choice
    [[ "$choice" == "q" || "$choice" == "Q" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      num=$((choice))
      if (( num >= 1 && num <= ${#models[@]} )); then
        echo "${models[$((num - 1))]}"
        return 0
      fi
    fi
    echo "Invalid choice. Try again." >&2
  done
}

# --- Update ~/.claude/settings.json ---
write_settings() {
  local model_id="$1"
  local schema="https://json.schemastore.org/claude-code-settings.json"
  local base_url="http://localhost:1234"
  local tmp
  tmp=$(mktemp)
  if command -v jq &>/dev/null; then
    jq -n \
      --arg schema "$schema" \
      --arg base "$base_url" \
      --arg model "$model_id" \
      '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_AUTH_TOKEN": "lmstudio", "ANTHROPIC_API_KEY": ""}, "defaultModel": $model}' \
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
    \"defaultModel\": \"$model_id\"
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
  echo "Claudius v${VERSION} - Claude Code + LM Studio (direct)"
  echo "LM Studio URL: $LMSTUDIO_URL"
  echo ""

  until check_server; do
    wait_for_server
  done

  local model_id
  model_id=$(select_model) || exit 1
  echo ""
  echo "Selected: $model_id"
  echo ""

  echo "Writing config..."
  write_settings "$model_id"
  update_bashrc
  verify_and_export "$model_id"

  echo "Starting Claude Code..."
  echo ""
  exec claude --model "$model_id"
}

main "$@"
