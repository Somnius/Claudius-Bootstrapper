#!/usr/bin/env bash
# Claudius v0.9.7 - Claude Code multi-backend bootstrapper (LM Studio, Ollama, llama.cpp server, OpenRouter, Custom, NewAPI).
# Author: Lefteris Iliadis (Somnius) https://github.com/Somnius
# Check server, pick model, set context (where applicable), update config, run claude.
# Supports: bash, zsh, fish, ksh, sh. Platforms: Linux, macOS, Windows (Git Bash/WSL).

set -euo pipefail

VERSION="0.9.7"

# --help function: Display usage information
print_help() {
  cat << 'EOF'
Usage: claudius [OPTIONS]

Claudius v0.9.7 - Claude Code multi-backend bootstrapper

Connects Claude Code (Anthropic's agentic CLI) to LM Studio, Ollama, llama.cpp server (llama-server),
OpenRouter, Custom (many presets), or NewAPI (QuantumNous unified gateway). Custom presets: Alibaba, Kimi,
DeepSeek, Groq, OpenRouter, xAI, OpenAI, or Other. NewAPI: self-host or cloud; chat at base/v1, list models at base/api/models.
Writes env vars to your shell config (bash/zsh/fish/ksh/sh).

Options:
  --help, -h    Show this help message and exit
  --init        Reset preferences and backend (show reply duration, keep session, which backend)
  --purge       Interactive menu to purge saved Claude Code session data
  --dry-run     Test flow without writing config or starting Claude
  --test        Alias for --dry-run
  --by-pass-start  Do not ask to start Claude Code after setup; exit once config is written (for use in scripts)
  --last           Use last base URL, model, and context length; skip model menu and start Claude Code

Environment Variables:
  CLAUDIUS_BACKEND   Backend: lmstudio | ollama | llamacpp | openrouter | custom | newapi
  LMSTUDIO_URL       LM Studio base URL (default: http://localhost:1234)
  OLLAMA_URL         Ollama base URL (default: http://localhost:11434)
  LLAMA_CPP_URL      llama-server base URL (default: http://127.0.0.1:8080)
  CLAUDIUS_AUTH_TOKEN  Override ANTHROPIC_AUTH_TOKEN (e.g. for llamacpp; default from prefs or lmstudio)
  CLAUDIUS_BASE_URL  Override base URL (custom, openrouter, newapi, or llamacpp)
  CLAUDIUS_API_KEY   API key in prefs; for OpenRouter and Alibaba DashScope …/apps/anthropic (custom) written to settings as ANTHROPIC_AUTH_TOKEN with ANTHROPIC_API_KEY ""
  OPENROUTER_URL     Default https://openrouter.ai/api (do not use .../api/v1 for Claude Code)
  CURL_TIMEOUT_CLOUD Max time (seconds) for OpenRouter/custom model-list HTTP; default 25 (default CURL_TIMEOUT is 10)
  DASHSCOPE_INTL_ANTHROPIC_BASE / DASHSCOPE_INTL_OPENAI_BASE  Override Alibaba intl. Anthropic vs OpenAI list URLs (advanced)
  CLAUDIUS_SHELL     Override shell for config file (bash|zsh|fish|ksh|sh)

Examples:
  claudius                          # Run full flow: choose backend, model, start Claude
  claudius --init                   # Reset preferences and re-choose backend
  claudius --init --by-pass-start   # Re-choose backend and model, write config, then exit (no start prompt)
  claudius --purge                  # Clear session data interactively
  claudius --last                   # Use last model and context; start Claude without menus
  CLAUDIUS_BACKEND=ollama claudius  # Use Ollama (if already configured)
  CLAUDIUS_BACKEND=llamacpp claudius # llama-server (default URL/token from prefs or LLAMA_CPP_URL)

For more info: https://github.com/Somnius/Claudius-Bootstrapper
EOF
}

# Paths and defaults
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"
CLAUDIUS_PREFS="${HOME}/.claude/claudius-prefs.json"
CLAUDE_HOME="${HOME}/.claude"
LMSTUDIO_URL="${LMSTUDIO_URL:-http://localhost:1234}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
LLAMA_CPP_URL="${LLAMA_CPP_URL:-http://127.0.0.1:8080}"
# Claude Code appends /v1/messages — OpenRouter requires host .../api only (NOT .../api/v1). See openrouter.ai/docs Claude Code guide.
OPENROUTER_URL="${OPENROUTER_URL:-https://openrouter.ai/api}"
LMSTUDIO_API="${LMSTUDIO_URL}/api/v1"

# Session-related paths under ~/.claude to purge (do not include settings.json or claudius-prefs.json)
SESSION_DIRS="projects debug file-history tasks todos plans shell-snapshots session-env paste-cache"

# Curl timeout: connect + max total (avoid hanging)
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"
# Cloud APIs (OpenRouter, custom): longer timeout + retries (Alibaba intl. can be slow or flaky on short timeouts)
CURL_TIMEOUT_CLOUD="${CURL_TIMEOUT_CLOUD:-25}"
# Alibaba Cloud DashScope (Singapore / intl.): OpenAI-compatible list vs Anthropic Messages for Claude Code — see README
DASHSCOPE_INTL_OPENAI_BASE="${DASHSCOPE_INTL_OPENAI_BASE:-https://dashscope-intl.aliyuncs.com/compatible-mode/v1}"
DASHSCOPE_INTL_ANTHROPIC_BASE="${DASHSCOPE_INTL_ANTHROPIC_BASE:-https://dashscope-intl.aliyuncs.com/apps/anthropic}"

# --- Platform detection: linux, darwin, or windows ---
detect_platform() {
  local u
  u=$(uname -s 2>/dev/null) || true
  case "$u" in
    Linux)   echo "linux" ;;
    Darwin)  echo "darwin" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)       echo "unknown" ;;
  esac
}

# --- Shell detection for config file and export syntax ---
# Output: bash, zsh, fish, ksh, or sh. Prefer CLAUDIUS_SHELL, then SHELL, then infer.
get_current_shell() {
  if [[ -n "${CLAUDIUS_SHELL:-}" ]]; then
    case "${CLAUDIUS_SHELL}" in
      bash|zsh|fish|ksh|sh) echo "${CLAUDIUS_SHELL}"; return ;;
    esac
  fi
  if [[ -n "${SHELL:-}" ]]; then
    case "$SHELL" in
      *fish*) echo "fish"; return ;;
      *zsh*)  echo "zsh"; return ;;
      *ksh*)  echo "ksh"; return ;;
      *bash*) echo "bash"; return ;;
    esac
  fi
  [[ -n "${BASH:-}" ]] && echo "bash" && return
  [[ -n "${ZSH_VERSION:-}" ]] && echo "zsh" && return
  [[ -n "${FISH_VERSION:-}" ]] && echo "fish" && return
  echo "bash"
}

# --- Config file path for the given shell ---
get_shell_config_file() {
  local shell="${1:-bash}"
  case "$shell" in
    fish) echo "${HOME}/.config/fish/config.fish" ;;
    zsh)  echo "${HOME}/.zshrc" ;;
    ksh)  echo "${HOME}/.kshrc" ;;
    sh)   echo "${HOME}/.profile" ;;
    *)    echo "${HOME}/.bashrc" ;;
  esac
}

# --- Absolute path to this script (for alias) ---
get_claudius_script_path() {
  local dir
  dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
  echo "${dir}/$(basename "${BASH_SOURCE[0]:-$0}")"
}

# --- Ensure ~/.local/bin is in shell config so 'claude' is in PATH in new terminals ---
ensure_path_for_claude_in_shell_config() {
  local shell="${1:-bash}" config_file
  config_file=$(get_shell_config_file "$shell")
  [[ -d "${HOME}/.local/bin" ]] || return 0
  if [[ -f "$config_file" ]] && grep -q '\.local/bin' "$config_file" 2>/dev/null; then
    return 0
  fi
  local marker="# Claudius: ensure Claude Code CLI (claude) in PATH"
  if [[ "$shell" == "fish" ]]; then
    mkdir -p "${HOME}/.config/fish"
    echo "" >> "$config_file"
    echo "$marker" >> "$config_file"
    echo 'set -gx PATH "$HOME/.local/bin" $PATH' >> "$config_file"
  else
    echo "" >> "$config_file"
    echo "$marker" >> "$config_file"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$config_file"
  fi
  echo "  Appended ~/.local/bin to PATH in $config_file (for Claude Code CLI)."
}

# --- Ensure claudius alias is in shell config so 'claudius' works in new terminals ---
ensure_claudius_alias_in_shell_config() {
  local shell="${1:-bash}" config_file script_path
  config_file=$(get_shell_config_file "$shell")
  script_path=$(get_claudius_script_path)
  if [[ -f "$config_file" ]] && grep -qE 'alias claudius|function claudius' "$config_file" 2>/dev/null; then
    return 0
  fi
  local marker="# Claudius bootstrapper alias (run: claudius)"
  if [[ "$shell" == "fish" ]]; then
    mkdir -p "${HOME}/.config/fish"
    echo "" >> "$config_file"
    echo "$marker" >> "$config_file"
    echo "function claudius; $script_path \$argv; end" >> "$config_file"
  else
    echo "" >> "$config_file"
    echo "$marker" >> "$config_file"
    echo "alias claudius='$script_path'" >> "$config_file"
  fi
  echo "  Appended claudius alias to $config_file."
}

# --- Append Claude Code env block to the correct config file with correct syntax ---
# Args: shell, base_url, auth_token, api_key, backend
# OpenRouter: ANTHROPIC_AUTH_TOKEN + empty ANTHROPIC_API_KEY (OpenRouter docs). Alibaba DashScope /apps/anthropic (custom): same pattern (imported from v0.9.4 GitHub). Other custom|newapi: API_KEY only. lmstudio|ollama|llamacpp: AUTH_TOKEN.
update_shell_exports() {
  local shell="${1:-bash}" base_url="$2" auth_token="${3:-}" api_key="${4:-}" backend="${5:-lmstudio}"
  local config_file marker block
  local dashscope_anthropic=0
  [[ "$backend" == "custom" && "$base_url" == *"dashscope"* && "$base_url" == *"/apps/anthropic"* ]] && dashscope_anthropic=1
  config_file=$(get_shell_config_file "$shell")
  marker="# Claude Code → Claudius (ANTHROPIC_BASE_URL for backend)"

  if [[ -f "$config_file" ]] && grep -q "ANTHROPIC_BASE_URL" "$config_file" 2>/dev/null && grep -q "$marker" "$config_file" 2>/dev/null; then
    echo "  Shell config already contains Claude Code env block: $config_file"
    return 0
  fi

  if [[ "$shell" == "fish" ]]; then
    mkdir -p "${HOME}/.config/fish"
    case "$backend" in
      openrouter)
        block="set -gx ANTHROPIC_BASE_URL \"${base_url}\"
set -gx ANTHROPIC_AUTH_TOKEN \"${api_key}\"
set -gx ANTHROPIC_API_KEY \"\"
set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0" ;;
      custom)
        if [[ $dashscope_anthropic -eq 1 ]]; then
          block="set -gx ANTHROPIC_BASE_URL \"${base_url}\"
set -gx ANTHROPIC_AUTH_TOKEN \"${api_key}\"
set -gx ANTHROPIC_API_KEY \"\"
set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0"
        else
          block="set -gx ANTHROPIC_BASE_URL \"${base_url}\"
set -gx ANTHROPIC_API_KEY \"${api_key}\"
set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0"
        fi ;;
      newapi)
        block="set -gx ANTHROPIC_BASE_URL \"${base_url}\"
set -gx ANTHROPIC_API_KEY \"${api_key}\"
set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0" ;;
      llamacpp)
        block="set -gx ANTHROPIC_BASE_URL \"${base_url}\"
set -gx ANTHROPIC_AUTH_TOKEN \"${auth_token}\"
set -gx ANTHROPIC_API_KEY \"\"
set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0
set -gx ENABLE_TOOL_SEARCH true
set -gx CLAUDE_CODE_AUTO_COMPACT_WINDOW 100000" ;;
      *)
        block="set -gx ANTHROPIC_BASE_URL \"${base_url}\"
set -gx ANTHROPIC_AUTH_TOKEN \"${auth_token}\"
set -gx CLAUDE_CODE_ATTRIBUTION_HEADER 0" ;;
    esac
  else
    case "$backend" in
      openrouter)
        block="export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_AUTH_TOKEN=\"${api_key}\"
export ANTHROPIC_API_KEY=\"\"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0" ;;
      custom)
        if [[ $dashscope_anthropic -eq 1 ]]; then
          block="export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_AUTH_TOKEN=\"${api_key}\"
export ANTHROPIC_API_KEY=\"\"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0"
        else
          block="export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_API_KEY=\"${api_key}\"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0"
        fi ;;
      newapi)
        block="export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_API_KEY=\"${api_key}\"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0" ;;
      llamacpp)
        block="export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_AUTH_TOKEN=\"${auth_token}\"
export ANTHROPIC_API_KEY=\"\"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0
export ENABLE_TOOL_SEARCH=true
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000" ;;
      *)
        block="export ANTHROPIC_BASE_URL=\"${base_url}\"
export ANTHROPIC_AUTH_TOKEN=\"${auth_token}\"
export CLAUDE_CODE_ATTRIBUTION_HEADER=0" ;;
    esac
  fi

  echo "" >> "$config_file"
  echo "$marker" >> "$config_file"
  echo "$block" >> "$config_file"
  echo "  Appended Claude Code env block to: $config_file"
  echo "  Reload with: source $config_file  (or open a new terminal)."
}

# --- First-time checks: LM Studio and required commands (run when prefs missing) ---
# Returns 0 if LM Studio appears installed (lms in PATH or common path), 1 otherwise.
check_lm_studio_installed() {
  if command -v lms &>/dev/null; then
    return 0
  fi
  [[ -x "${HOME}/.lmstudio/bin/lms" ]] && return 0
  [[ -x "/opt/LM Studio/bin/lms" ]] 2>/dev/null && return 0
  echo "LM Studio does not appear to be installed (no 'lms' command found)."
  echo "  Download and install from: https://lmstudio.ai/"
  echo "  Then run this script again with: claudius --init"
  echo ""
  return 1
}

# Returns 0 if Ollama appears installed (ollama in PATH), 1 otherwise.
check_ollama_installed() {
  if command -v ollama &>/dev/null; then
    return 0
  fi
  echo "Ollama does not appear to be installed (no 'ollama' command found)."
  echo "  Install from: https://ollama.com"
  echo "  Then run this script again with: claudius --init"
  echo ""
  return 1
}

# --- Try to install Claude Code CLI (Linux/macOS via official install script) ---
# Returns 0 if claude is in PATH after attempt, 1 otherwise. Adds ~/.local/bin to PATH for session.
try_install_claude_code() {
  local plat
  plat=$(detect_platform)
  if [[ "$plat" == "windows" ]]; then
    echo "  On Windows, install Claude Code via WSL or see https://code.claude.com/docs"
    return 1
  fi
  echo "  Running official install script (https://claude.ai/install.sh)..."
  if ! curl -fsSL https://claude.ai/install.sh 2>/dev/null | bash 2>/dev/null; then
    echo "  Install script failed or returned an error."
    return 1
  fi
  export PATH="${HOME}/.local/bin:${PATH}"
  if command -v claude &>/dev/null; then
    echo "  Claude Code installed. Run 'claude --version' to confirm."
    ensure_path_for_claude_in_shell_config "$(get_current_shell)"
    return 0
  fi
  echo "  Install may have completed. Ensuring ~/.local/bin in your shell config..."
  ensure_path_for_claude_in_shell_config "$(get_current_shell)"
  echo "  Reload your shell (source config file) or open a new terminal, then run claudius again."
  return 1
}

# --- Ensure Claude Code CLI is installed; offer install if missing; persist PATH/alias in shell config ---
# Returns 0 if claude is available (now or after install), 1 otherwise.
ensure_claude_installed() {
  [[ -d "${HOME}/.local/bin" ]] && export PATH="${HOME}/.local/bin:${PATH}"
  if command -v claude &>/dev/null; then
    return 0
  fi
  echo "Claude Code CLI (claude) is not installed or not in your PATH."
  echo ""
  local install_choice="y"
  read -rp "Install Claude Code now? [Y/n]: " install_choice
  install_choice="${install_choice:-y}"
  if [[ "${install_choice,,}" != "n" && "${install_choice,,}" != "no" ]]; then
    if try_install_claude_code; then
      return 0
    fi
  fi
  local cfg
  cfg=$(get_shell_config_file "$(get_current_shell)")
  ensure_path_for_claude_in_shell_config "$(get_current_shell)"
  echo "  Then run: source $cfg  or open a new terminal, and run claudius again."
  return 1
}

# Check required commands (curl; jq or python3; claude). Returns 0 if all ok, 1 otherwise. Prints install hints.
check_required_commands() {
  local missing=()
  # Prefer ~/.local/bin so we detect Claude Code if installed there but not yet in PATH (e.g. fresh install, IDE shell)
  [[ -d "${HOME}/.local/bin" ]] && export PATH="${HOME}/.local/bin:${PATH}"
  command -v curl &>/dev/null || missing+=("curl")
  if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
    missing+=("jq or python3 (at least one for JSON)")
  fi
  command -v claude &>/dev/null || missing+=("claude (Claude Code CLI)")

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  # If only claude is missing, offer to install it
  if [[ ${#missing[@]} -eq 1 && "${missing[0]}" == *"claude"* ]]; then
    if ensure_claude_installed; then
      return 0
    fi
  fi

  echo "Missing required command(s): ${missing[*]}"
  echo ""
  echo "Install on your system, then run this script again with: claudius --init"
  echo ""
  local plat
  plat=$(detect_platform)
  case "$plat" in
    linux)
      if [[ -r /etc/os-release ]]; then
        local id_like id
        id=$(. /etc/os-release && echo "${ID:-}")
        id_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
        if [[ "$id" == "debian" || "$id" == "ubuntu" || "$id" == "pika" || "$id_like" == *"debian"* ]]; then
          echo "  Debian/Ubuntu/PikaOS: sudo apt install curl jq"
        elif [[ "$id" == "fedora" || "$id" == "rhel" || "$id_like" == *"fedora"* ]]; then
          echo "  Fedora/RHEL: sudo dnf install curl jq"
        elif [[ "$id" == "arch" || "$id_like" == *"arch"* ]]; then
          echo "  Arch: sudo pacman -S curl jq"
        else
          echo "  curl/jq: use your package manager (apt/dnf/pacman/zypper etc.)"
        fi
      else
        echo "  curl/jq: use your package manager"
      fi
      ;;
    darwin)
      echo "  macOS: brew install curl jq"
      ;;
    windows)
      echo "  Windows: use WSL or Git Bash and install curl/jq there, or install from https://curl.se / https://jqlang.github.io/jq/"
      ;;
    *)
      echo "  curl/jq: use your system package manager"
      ;;
  esac
  echo "  python3: usually preinstalled; if not, install via your package manager"
  echo "  claude:  see https://code.claude.com/docs for install instructions (Quickstart / your platform)"
  echo ""
  return 1
}

# --- Auth token for llamacpp: prefs authToken if key exists, else default lmstudio; explicit "" means no Bearer ---
get_llamacpp_auth_from_prefs() {
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    echo "lmstudio"
    return
  fi
  if command -v jq &>/dev/null; then
    if jq -e 'has("authToken")' "$CLAUDIUS_PREFS" &>/dev/null; then
      jq -r '.authToken // ""' "$CLAUDIUS_PREFS"
      return
    fi
    echo "lmstudio"
    return
  fi
  python3 -c "
import json
try:
    d = json.load(open('$CLAUDIUS_PREFS'))
    print(d['authToken'] if 'authToken' in d else 'lmstudio')
except Exception:
    print('lmstudio')
" 2>/dev/null || echo "lmstudio"
}

# --- Backend: read/save from prefs (backend, baseUrl, apiKey) ---
get_pref() {
  local key="$1"
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    echo ""
    return
  fi
  if command -v jq &>/dev/null; then
    jq -r --arg k "$key" '.[$k] // ""' "$CLAUDIUS_PREFS" 2>/dev/null || echo ""
  else
    python3 -c "import json; f=open('$CLAUDIUS_PREFS'); d=json.load(f); print(d.get('$key', '') or '')" 2>/dev/null || echo ""
  fi
}

# Merge new keys into existing prefs JSON (preserves showTurnDuration, keepSessionOnExit, etc.)
# Optional 4th arg: authToken (for llamacpp). If omitted, existing .authToken is left unchanged.
merge_prefs() {
  local backend="$1" base_url="$2" api_key="${3:-}"
  mkdir -p "$(dirname "$CLAUDIUS_PREFS")"
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    local at="${4:-}"
    if command -v jq &>/dev/null; then
      jq -n --arg b "$backend" --arg u "$base_url" --arg k "$api_key" --arg at "$at" \
        '{backend: $b, baseUrl: $u, apiKey: $k, authToken: $at, showTurnDuration: true, keepSessionOnExit: true}' > "$CLAUDIUS_PREFS"
    else
      printf '%s\n' "{\"backend\": \"$backend\", \"baseUrl\": \"$base_url\", \"apiKey\": \"$api_key\", \"authToken\": \"$at\", \"showTurnDuration\": true, \"keepSessionOnExit\": true}" > "$CLAUDIUS_PREFS"
    fi
    return
  fi
  if command -v jq &>/dev/null; then
    if [[ $# -ge 4 ]]; then
      jq --arg b "$backend" --arg u "$base_url" --arg k "$api_key" --arg at "$4" \
        '.backend = $b | .baseUrl = $u | .apiKey = $k | .authToken = $at' "$CLAUDIUS_PREFS" > "${CLAUDIUS_PREFS}.tmp" && mv "${CLAUDIUS_PREFS}.tmp" "$CLAUDIUS_PREFS"
    else
      jq --arg b "$backend" --arg u "$base_url" --arg k "$api_key" \
        '.backend = $b | .baseUrl = $u | .apiKey = $k' "$CLAUDIUS_PREFS" > "${CLAUDIUS_PREFS}.tmp" && mv "${CLAUDIUS_PREFS}.tmp" "$CLAUDIUS_PREFS"
    fi
  else
    if [[ $# -ge 4 ]]; then
      CLAUDIUS_MERGE_AT="$4" python3 -c "
import json, os
at = os.environ.get('CLAUDIUS_MERGE_AT', '')
with open('$CLAUDIUS_PREFS') as f: d = json.load(f)
d['backend'] = '$backend'
d['baseUrl'] = '$base_url'
d['apiKey'] = '$api_key'
d['authToken'] = at
with open('$CLAUDIUS_PREFS','w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || true
    else
      python3 -c "
import json
with open('$CLAUDIUS_PREFS') as f: d = json.load(f)
d['backend'] = '$backend'
d['baseUrl'] = '$base_url'
d['apiKey'] = '$api_key'
with open('$CLAUDIUS_PREFS','w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || true
    fi
  fi
}

# --- Save last selected model and context length to prefs (for --last) ---
save_last_model_prefs() {
  local model_id="$1" context_length="${2:-32768}"
  [[ ! -f "$CLAUDIUS_PREFS" ]] && return 0
  if command -v jq &>/dev/null; then
    jq --arg m "$model_id" --argjson c "$context_length" '.lastModel = $m | .lastContextLength = $c' "$CLAUDIUS_PREFS" > "${CLAUDIUS_PREFS}.tmp" && mv "${CLAUDIUS_PREFS}.tmp" "$CLAUDIUS_PREFS"
  else
    python3 -c "
import json
with open('$CLAUDIUS_PREFS') as f: d = json.load(f)
d['lastModel'] = '$model_id'
d['lastContextLength'] = $context_length
with open('$CLAUDIUS_PREFS','w') as f: json.dump(d, f, indent=2)
" 2>/dev/null || true
  fi
}

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

  echo "Which backend should Claudius use?"
  echo "  1) LM Studio (local, default http://localhost:1234)"
  echo "  2) Ollama (local, default http://localhost:11434)"
  echo "  3) OpenRouter (cloud; Claude Code base https://openrouter.ai/api — requires API key)"
  echo "  4) Custom (Alibaba, Kimi, DeepSeek, Groq, OpenRouter, xAI, OpenAI, or other — API key)"
  echo "  5) NewAPI (unified gateway — self‑host or cloud, https://github.com/QuantumNous/new-api)"
  echo "  6) llama.cpp server (llama-server, OpenAI-compatible /v1; default http://127.0.0.1:8080)"
  echo ""
  local backend_choice backend="lmstudio" base_url="$LMSTUDIO_URL" api_key="" auth_token_save=""
  read -rp "Choose (1-6) [1]: " backend_choice
  backend_choice="${backend_choice:-1}"
  case "$backend_choice" in
    1) backend="lmstudio"; base_url="${LMSTUDIO_URL}"; api_key="" ;;
    2) backend="ollama";   base_url="${OLLAMA_URL}"; api_key="" ;;
    3)
      backend="openrouter"
      base_url="${OPENROUTER_URL}"
      read -rp "OpenRouter API key: " api_key
      [[ -z "$api_key" ]] && echo "  Warning: API key empty; list models may fail." >&2
      ;;
    5)
      backend="newapi"
      read -rp "NewAPI base URL (e.g. http://localhost:8080 or https://your-newapi-host): " base_url
      base_url="${base_url:-http://localhost:8080}"
      read -rp "NewAPI API key (Bearer token): " api_key
      [[ -z "$api_key" ]] && echo "  Warning: API key empty; list models may fail." >&2
      ;;
    4)
      backend="custom"
      echo "Choose custom provider (OpenAI-compatible API):"
      echo "  1) Alibaba Cloud (DashScope) — Singapore: Anthropic API base for Claude Code (${DASHSCOPE_INTL_ANTHROPIC_BASE})"
      echo "  2) Kimi (Moonshot AI) — global: api.moonshot.ai"
      echo "  3) DeepSeek — api.deepseek.com"
      echo "  4) Groq — api.groq.com/openai/v1"
      echo "  5) OpenRouter — openrouter.ai (same as backend 3, alternative entry)"
      echo "  6) xAI (Grok) — api.x.ai"
      echo "  7) OpenAI — api.openai.com"
      echo "  8) Other — enter base URL and API key"
      echo ""
      local custom_choice
      read -rp "Choose (1-8) [1]: " custom_choice
      custom_choice="${custom_choice:-1}"
      case "$custom_choice" in
        1) base_url="${DASHSCOPE_INTL_ANTHROPIC_BASE}" ;;
        2) base_url="https://api.moonshot.ai/v1" ;;
        3) base_url="https://api.deepseek.com/v1" ;;
        4) base_url="https://api.groq.com/openai/v1" ;;
        5) base_url="${OPENROUTER_URL}" ;;
        6) base_url="https://api.x.ai/v1" ;;
        7) base_url="https://api.openai.com/v1" ;;
        8)
          read -rp "Custom API base URL (e.g. https://api.example.com/v1): " base_url
          ;;
        *) base_url="${DASHSCOPE_INTL_ANTHROPIC_BASE}" ;;
      esac
      read -rp "API key: " api_key
      [[ -z "$api_key" ]] && echo "  Warning: API key empty; list models may fail." >&2
      [[ "$custom_choice" == "8" && -z "$base_url" ]] && echo "  Warning: Base URL empty; list models may fail." >&2
      ;;
    6)
      backend="llamacpp"
      read -rp "llama.cpp server base URL [http://127.0.0.1:8080]: " base_url
      base_url="${base_url:-http://127.0.0.1:8080}"
      local llama_tok
      read -rp "Bearer/API token → ANTHROPIC_AUTH_TOKEN [lmstudio]: " llama_tok
      llama_tok="${llama_tok:-lmstudio}"
      auth_token_save="$llama_tok"
      api_key=""
      ;;
    *) backend="lmstudio"; base_url="${LMSTUDIO_URL}"; api_key="" ;;
  esac

  mkdir -p "$(dirname "$CLAUDIUS_PREFS")"
  if command -v jq &>/dev/null; then
    jq -n \
      --arg st "$show_turn_bool" --arg ks "$keep_sess_bool" \
      --arg b "$backend" --arg u "$base_url" --arg k "$api_key" --arg at "$auth_token_save" \
      '{showTurnDuration: ($st == "true"), keepSessionOnExit: ($ks == "true"), backend: $b, baseUrl: $u, apiKey: $k, authToken: $at}' > "$CLAUDIUS_PREFS"
  else
    CLAUDIUS_INIT_AT="$auth_token_save" python3 -c "
import json, os
d = {
    'showTurnDuration': $show_turn_bool,
    'keepSessionOnExit': $keep_sess_bool,
    'backend': '$backend',
    'baseUrl': '$base_url',
    'apiKey': '$api_key',
    'authToken': os.environ.get('CLAUDIUS_INIT_AT', ''),
}
with open('$CLAUDIUS_PREFS', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || printf '%s\n' "{\"showTurnDuration\": $show_turn_bool, \"keepSessionOnExit\": $keep_sess_bool, \"backend\": \"$backend\", \"baseUrl\": \"$base_url\", \"apiKey\": \"$api_key\", \"authToken\": \"\"}" > "$CLAUDIUS_PREFS"
  fi
  echo "  Saved. Run claudius --init again anytime to change these."
  echo ""
}

# --- Read showTurnDuration from prefs; default true. Must output lowercase "true" or "false" for write_settings. ---
get_show_turn_duration() {
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    echo "true"
    return
  fi
  if command -v jq &>/dev/null; then
    jq -r '(.showTurnDuration // true) | if . then "true" else "false" end' "$CLAUDIUS_PREFS" 2>/dev/null || echo "true"
  else
    python3 -c "import json; v=json.load(open('$CLAUDIUS_PREFS')).get('showTurnDuration', True); print('true' if v else 'false')" 2>/dev/null || echo "true"
  fi
}

# --- Read keepSessionOnExit from prefs; default true. Output lowercase "true" or "false" for main. ---
get_keep_session_on_exit() {
  if [[ ! -f "$CLAUDIUS_PREFS" ]]; then
    echo "true"
    return
  fi
  if command -v jq &>/dev/null; then
    jq -r '(.keepSessionOnExit // true) | if . then "true" else "false" end' "$CLAUDIUS_PREFS" 2>/dev/null || echo "true"
  else
    python3 -c "import json; v=json.load(open('$CLAUDIUS_PREFS')).get('keepSessionOnExit', True); print('true' if v else 'false')" 2>/dev/null || echo "true"
  fi
}

# --- PURGE SAFETY: Session data is destructive. ---
# These functions must ONLY be called from run_purge() or run_after_session_menu(),
# and ONLY for the specific option the user chose. Never call a purge automatically
# or from any path that does not require explicit user input for that choice.

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
  echo "  2) Purge last session only (last ~2 min)"
  echo "  3) Purge all from yesterday and back"
  echo "  4) Purge all from 6 hours and back"
  echo "  5) Purge all from 3 hours and back"
  echo "  6) Purge all from 2 hours and back"
  echo "  7) Purge all from 1 hour and back"
  echo "  8) Purge all from 30 minutes and back"
  echo "  q) Cancel"
  echo ""

  local choice
  read -rp "Choose (1-8 or q): " choice
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
    2) purge_session_recent; echo "  Purged last session only." ;;
    3) purge_yesterday_and_back; echo "  Purged session data from yesterday and back." ;;
    4) purge_older_than_mins 360; echo "  Purged session data older than 6 hours." ;;
    5) purge_older_than_mins 180; echo "  Purged session data older than 3 hours." ;;
    6) purge_older_than_mins 120; echo "  Purged session data older than 2 hours." ;;
    7) purge_older_than_mins 60;  echo "  Purged session data older than 1 hour." ;;
    8) purge_older_than_mins 30;  echo "  Purged session data older than 30 minutes." ;;
    *) echo "Invalid choice. No data purged."; return 0 ;;
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
  # Only the exact option chosen by the user triggers a purge; anything else skips.
  case "$choice" in
    1) purge_session_recent; echo "  Deleted current session." ;;
    2)
      read -rp "Type YES to confirm purge of ALL session data: " a
      [[ "${a^^}" != "YES" ]] && echo "Skipped. No data purged." && return 0
      read -rp "Type PURGE to confirm again: " b
      [[ "${b^^}" != "PURGE" ]] && echo "Skipped. No data purged." && return 0
      purge_session_dirs 1
      echo "  Purged all session data."
      ;;
    3) purge_yesterday_and_back; echo "  Purged session data from yesterday and back." ;;
    4) purge_older_than_mins 360; echo "  Purged session data older than 6 hours." ;;
    5) purge_older_than_mins 180; echo "  Purged session data older than 3 hours." ;;
    6) purge_older_than_mins 120; echo "  Purged session data older than 2 hours." ;;
    7) purge_older_than_mins 60;  echo "  Purged session data older than 1 hour." ;;
    8) purge_older_than_mins 30;  echo "  Purged session data older than 30 minutes." ;;
    9|q|Q) echo "  Skipped. No data purged." ;;
    *) echo "  Skipped. No data purged." ;;
  esac
  return 0
}

# --- Normalize user-entered server address to base URL (http://host:port) ---
# Args: address (e.g. 192.168.1.10:1234, myserver, http://host:11434), default_port
# Output: base URL (no trailing slash)
normalize_remote_url() {
  local raw="${1:-}" default_port="${2:-1234}"
  raw=$(echo "$raw" | tr -d ' \t')
  [[ -z "$raw" ]] && echo "" && return 1
  if [[ "$raw" == https://* || "$raw" == http://* ]]; then
    echo "${raw%/}"
    return 0
  fi
  if [[ "$raw" =~ ^([^:]+):([0-9]+)$ ]]; then
    echo "http://${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    return 0
  fi
  echo "http://${raw}:${default_port}"
  return 0
}

# --- Prompt for remote server address and backend type; set CURRENT_BASE_URL, CURRENT_BACKEND and save to prefs ---
prompt_remote_server() {
  local addr backend_num default_port
  echo "Connect to a remote server (e.g. another machine on your network)."
  read -rp "Enter server address (host or IP:port, e.g. 192.168.1.10:1234): " addr
  addr=$(echo "$addr" | tr -d ' \t')
  if [[ -z "$addr" ]]; then
    echo "  No address entered. Skipped."
    return 1
  fi
  echo ""
  echo "Backend running on this server:"
  echo "  1) LM Studio (default port 1234)"
  echo "  2) Ollama (default port 11434)"
  echo "  3) llama.cpp server / llama-server (default port 8080)"
  read -rp "Choose (1-3) [1]: " backend_num
  backend_num="${backend_num:-1}"
  case "$backend_num" in
    1) CURRENT_BACKEND="lmstudio"; default_port=1234 ;;
    2) CURRENT_BACKEND="ollama";   default_port=11434 ;;
    3) CURRENT_BACKEND="llamacpp";  default_port=8080 ;;
    *) echo "  Invalid choice. Using LM Studio (1234)."; CURRENT_BACKEND="lmstudio"; default_port=1234 ;;
  esac
  CURRENT_BASE_URL=$(normalize_remote_url "$addr" "$default_port")
  if [[ -z "$CURRENT_BASE_URL" ]]; then
    echo "  Could not parse address. Skipped."
    return 1
  fi
  case "$CURRENT_BACKEND" in
    lmstudio) CURRENT_AUTH="lmstudio" ;;
    ollama)   CURRENT_AUTH="" ;;
    llamacpp)
      CURRENT_AUTH=$(get_llamacpp_auth_from_prefs)
      ;;
    *)        CURRENT_AUTH="$CURRENT_API_KEY" ;;
  esac
  merge_prefs "$CURRENT_BACKEND" "$CURRENT_BASE_URL" "$CURRENT_API_KEY"
  echo "  Using $CURRENT_BACKEND @ $CURRENT_BASE_URL"
  return 0
}

# --- Resolve backend from env or prefs; set CURRENT_BACKEND, CURRENT_BASE_URL, CURRENT_API_KEY, CURRENT_AUTH ---
resolve_backend() {
  if [[ -n "${CLAUDIUS_BACKEND:-}" ]]; then
    CURRENT_BACKEND="$CLAUDIUS_BACKEND"
    CURRENT_BASE_URL="${CLAUDIUS_BASE_URL:-}"
    CURRENT_API_KEY="${CLAUDIUS_API_KEY:-}"
  else
    CURRENT_BACKEND=$(get_pref "backend")
    CURRENT_BASE_URL=$(get_pref "baseUrl")
    CURRENT_API_KEY=$(get_pref "apiKey")
  fi
  # Defaults when empty
  [[ -z "$CURRENT_BACKEND" ]] && CURRENT_BACKEND="lmstudio"
  if [[ -z "$CURRENT_BASE_URL" ]]; then
    case "$CURRENT_BACKEND" in
      lmstudio) CURRENT_BASE_URL="${LMSTUDIO_URL}" ;;
      ollama)   CURRENT_BASE_URL="${OLLAMA_URL}" ;;
      llamacpp) CURRENT_BASE_URL="${LLAMA_CPP_URL}" ;;
      openrouter) CURRENT_BASE_URL="${OPENROUTER_URL}" ;;
      newapi)   ;;  # no default; user must set in prefs
      *)        CURRENT_BASE_URL="" ;;
    esac
  fi
  [[ -z "$CURRENT_API_KEY" ]] && CURRENT_API_KEY=""
  # Auth token for Claude Code settings: LM Studio uses placeholder; llamacpp uses prefs or env; cloud uses API key
  case "$CURRENT_BACKEND" in
    lmstudio) CURRENT_AUTH="lmstudio" ;;
    ollama)   CURRENT_AUTH="" ;;
    llamacpp)
      CURRENT_AUTH="${CLAUDIUS_AUTH_TOKEN:-}"
      [[ -z "$CURRENT_AUTH" ]] && CURRENT_AUTH=$(get_llamacpp_auth_from_prefs)
      ;;
    *)       CURRENT_AUTH="$CURRENT_API_KEY" ;;
  esac

  # Alibaba DashScope (intl.): Claude Code uses Anthropic Messages → ANTHROPIC_BASE_URL must be .../apps/anthropic (not .../compatible-mode/v1).
  # Model listing uses OpenAI-compatible .../compatible-mode/v1. See https://www.alibabacloud.com/help/en/model-studio/anthropic-api-messages
  unset -v CURRENT_CUSTOM_LIST_URL 2>/dev/null || true
  if [[ "$CURRENT_BACKEND" == "custom" ]]; then
    if [[ "$CURRENT_BASE_URL" == *"dashscope-intl.aliyuncs.com"* ]]; then
      if [[ "$CURRENT_BASE_URL" == *"/compatible-mode"* ]]; then
        local dashscope_migrate_prefs=0
        CURRENT_CUSTOM_LIST_URL="$CURRENT_BASE_URL"
        if [[ -z "${CLAUDIUS_BACKEND:-}" && -z "${CLAUDIUS_BASE_URL:-}" && -f "$CLAUDIUS_PREFS" ]]; then
          local saved_base
          saved_base=$(get_pref "baseUrl")
          [[ "$saved_base" == *"/compatible-mode"* ]] && dashscope_migrate_prefs=1
        fi
        CURRENT_BASE_URL="$DASHSCOPE_INTL_ANTHROPIC_BASE"
        if [[ "$dashscope_migrate_prefs" -eq 1 ]]; then
          merge_prefs "custom" "$CURRENT_BASE_URL" "$CURRENT_API_KEY" || true
          echo "  Updated prefs: Alibaba base URL → ${DASHSCOPE_INTL_ANTHROPIC_BASE} (Anthropic API for Claude Code). Model list: ${CURRENT_CUSTOM_LIST_URL}." >&2
        fi
      elif [[ "$CURRENT_BASE_URL" == *"/apps/anthropic"* ]]; then
        CURRENT_CUSTOM_LIST_URL="$DASHSCOPE_INTL_OPENAI_BASE"
      else
        CURRENT_CUSTOM_LIST_URL="$CURRENT_BASE_URL"
      fi
    else
      CURRENT_CUSTOM_LIST_URL="$CURRENT_BASE_URL"
    fi
  fi

  # OpenRouter: ANTHROPIC_BASE_URL must be https://openrouter.ai/api (Claude Code adds /v1/messages). Old .../api/v1 breaks chat.
  if [[ "$CURRENT_BACKEND" == "openrouter" ]]; then
    if [[ "$CURRENT_BASE_URL" == *"openrouter.ai/api/v1"* ]]; then
      local or_migrate_prefs=0
      if [[ -z "${CLAUDIUS_BACKEND:-}" && -z "${CLAUDIUS_BASE_URL:-}" && -f "$CLAUDIUS_PREFS" ]]; then
        local saved_or
        saved_or=$(get_pref "baseUrl")
        [[ "$saved_or" == *"openrouter.ai/api/v1"* ]] && or_migrate_prefs=1
      fi
      CURRENT_BASE_URL="https://openrouter.ai/api"
      if [[ "$or_migrate_prefs" -eq 1 ]]; then
        merge_prefs "openrouter" "$CURRENT_BASE_URL" "$CURRENT_API_KEY" || true
        echo "  Updated prefs: OpenRouter base URL → https://openrouter.ai/api (required for Claude Code; see OpenRouter docs)." >&2
      fi
    fi
  fi
}

# --- Check if LM Studio server is reachable ---
check_server_lmstudio() {
  local base_url="${1:-$LMSTUDIO_URL}"
  local api_base="${base_url}/api/v1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${api_base}/models" 2>/dev/null) || true
  [[ "$code" == "200" ]]
}

check_server() {
  check_server_lmstudio "${1:-$LMSTUDIO_URL}"
}

# --- Prompt when server is not running: Resume / Try start / Abort ---
# Backend-aware: LM Studio (lms server start), Ollama (ollama serve), OpenRouter/Custom (just Abort or retry).
wait_for_server() {
  if [[ "$CURRENT_BACKEND" == "lmstudio" ]]; then
    local api_base="${CURRENT_BASE_URL}/api/v1"
    local current_loaded=""
    local loaded_json
    loaded_json=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${api_base}/models" 2>/dev/null) || true
    if [[ -n "${loaded_json}" ]]; then
      current_loaded=$(echo "$loaded_json" | jq -r '.models[]?.loaded_instances[]?.id // empty' 2>/dev/null | head -1)
      if [[ -n "${current_loaded}" ]]; then
        echo "  Currently loaded: ${current_loaded} (will be unloaded before switching)" >&2
      fi
    fi
    echo "LM Studio server is not running at ${CURRENT_BASE_URL}."
    echo ""
    echo "  1) Resume       - I've started the server; check again."
    echo "  2) Start        - Try to start the server locally (runs: lms server start)."
    echo "  3) Remote       - Connect to a remote server (different machine, IP:port)."
    echo "  4) Abort        - Exit."
    echo ""
    local choice
    while true; do
      read -rp "Choose (1-4): " choice
      case "$choice" in
        1)
          if check_server_for_backend; then
            echo "Server is up. Continuing."
            return 0
          fi
          echo "Still not reachable. Start the server in LM Studio, then choose Resume again."
          echo ""
          ;;
        2)
          if command -v lms &>/dev/null; then
            echo "Starting LM Studio server in background (lms server start)..."
            lms server start &
            sleep 3
            if check_server_for_backend; then
              echo "Server is up. Continuing."
              return 0
            fi
            echo "Server may still be starting. Choose Resume to retry or Abort."
          else
            echo "Command 'lms' not found. Install LM Studio and ensure 'lms' is on your PATH."
            echo "Start the server from the LM Studio GUI, or choose Remote to use another machine."
          fi
          echo ""
          ;;
        3)
          if prompt_remote_server; then
            if check_server_for_backend; then
              echo "Server is up. Continuing."
              return 0
            fi
            echo "Still not reachable. Check address and that the server is running, then try again."
          fi
          echo ""
          ;;
        4) echo "Aborted."; exit 1 ;;
        *) echo "Invalid choice. Enter 1, 2, 3, or 4."; echo "" ;;
      esac
    done
  elif [[ "$CURRENT_BACKEND" == "ollama" ]]; then
    echo "Ollama server is not running at ${CURRENT_BASE_URL}."
    echo ""
    echo "  1) Resume       - I've started the server (e.g. ollama serve); check again."
    echo "  2) Start        - Try to start Ollama locally (runs: ollama serve in background)."
    echo "  3) Remote       - Connect to a remote server (different machine, IP:port)."
    echo "  4) Abort        - Exit."
    echo ""
    local choice
    while true; do
      read -rp "Choose (1-4): " choice
      case "$choice" in
        1)
          if check_server_for_backend; then
            echo "Server is up. Continuing."
            return 0
          fi
          echo "Still not reachable. Run 'ollama serve' in another terminal, then choose Resume."
          echo ""
          ;;
        2)
          if command -v ollama &>/dev/null; then
            echo "Starting Ollama in background (ollama serve)..."
            ollama serve &
            sleep 3
            if check_server_for_backend; then
              echo "Server is up. Continuing."
              return 0
            fi
            echo "Server may still be starting. Choose Resume to retry or Abort."
          else
            echo "Command 'ollama' not found. Install from https://ollama.com and run 'ollama serve', or choose Remote to use another machine."
          fi
          echo ""
          ;;
        3)
          if prompt_remote_server; then
            if check_server_for_backend; then
              echo "Server is up. Continuing."
              return 0
            fi
            echo "Still not reachable. Check address and that the server is running, then try again."
          fi
          echo ""
          ;;
        4) echo "Aborted."; exit 1 ;;
        *) echo "Invalid choice. Enter 1, 2, 3, or 4."; echo "" ;;
      esac
    done
  elif [[ "$CURRENT_BACKEND" == "llamacpp" ]]; then
    echo "llama.cpp server (llama-server) is not reachable at ${CURRENT_BASE_URL}."
    echo ""
    echo "  1) Resume       - I've started llama-server; check again."
    echo "  2) Remote       - Use a different host/port (another machine or bind address)."
    echo "  3) Abort        - Exit."
    echo ""
    local choice_llama
    while true; do
      read -rp "Choose (1-3): " choice_llama
      case "$choice_llama" in
        1)
          if check_server_for_backend; then
            echo "Server is up. Continuing."
            return 0
          fi
          echo "Still not reachable. Start llama-server, then choose Resume."
          echo ""
          ;;
        2)
          if prompt_remote_server; then
            if check_server_for_backend; then
              echo "Server is up. Continuing."
              return 0
            fi
            echo "Still not reachable. Check address and that llama-server is running."
          fi
          echo ""
          ;;
        3) echo "Aborted."; exit 1 ;;
        *) echo "Invalid choice. Enter 1, 2, or 3."; echo "" ;;
      esac
    done
  else
    # OpenRouter / custom: no local server to start
    echo "Cannot reach ${CURRENT_BACKEND} at ${CURRENT_BASE_URL}."
    echo ""
    echo "  1) Retry   - Check network and API key, then try again."
    echo "  2) Abort   - Exit."
    echo ""
    local choice
    while true; do
      read -rp "Choose (1-2): " choice
      case "$choice" in
        1)
          if check_server_for_backend; then
            echo "Connected. Continuing."
            return 0
          fi
          echo "Still not reachable. Check your API key and network."
          echo ""
          ;;
        2) echo "Aborted."; exit 1 ;;
        *) echo "Invalid choice. Enter 1 or 2."; echo "" ;;
      esac
    done
  fi
}

# --- Get currently loaded model in LM Studio: output "model_key|context_length" or empty ---
get_loaded_lmstudio_model() {
  local api_base="${1:-$LMSTUDIO_API}"
  local resp
  resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${api_base}/models" 2>/dev/null) || true
  [[ -z "$resp" ]] && return 1
  if command -v jq &>/dev/null; then
    local key ctx
    key=$(echo "$resp" | jq -r '.models[] | select((.loaded_instances | length) > 0) | .key' 2>/dev/null | head -1)
    [[ -z "$key" ]] && return 1
    ctx=$(echo "$resp" | jq -r --arg k "$key" '.models[] | select(.key == $k) | .loaded_instances[0].config.context_length // .loaded_instances[0].context_length // .max_context_length // 32768' 2>/dev/null | head -1)
    [[ -z "$ctx" ]] && ctx=32768
    echo "${key}|${ctx}"
    return 0
  fi
  python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('models', []):
        insts = m.get('loaded_instances') or []
        if not insts: continue
        key = m.get('key', '')
        cfg = insts[0]
        ctx = cfg.get('config', {}).get('context_length') or cfg.get('context_length') or m.get('max_context_length', 32768)
        if key: print(key + '|' + str(ctx)); sys.exit(0)
except Exception: pass
sys.exit(1)
" <<< "$resp" 2>/dev/null && return 0
  return 1
}

# --- Unload any currently loaded model(s) in LM Studio (avoids load conflicts / HTTP 500) ---
unload_loaded_models() {
  local api_base="${1:-$LMSTUDIO_API}"
  local resp ids id
  resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${api_base}/models" 2>/dev/null) || true
  [[ -z "$resp" ]] && return 0
  ids=()
  if command -v jq &>/dev/null; then
    while IFS= read -r id; do
      [[ -n "$id" ]] && ids+=("$id")
    done < <(echo "$resp" | jq -r '.models[]?.loaded_instances[]?.id // empty' 2>/dev/null)
  else
    while IFS= read -r id; do
      [[ -n "$id" ]] && ids+=("$id")
    done < <(echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('models', []):
        for inst in m.get('loaded_instances', []):
            i = inst.get('id')
            if i: print(i)
except Exception: pass
" 2>/dev/null)
  fi
  if [[ ${#ids[@]} -eq 0 ]]; then
    return 0
  fi
  echo "  Unloading previous model(s)..."
  for id in "${ids[@]}"; do
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 30 \
      -X POST -H "Content-Type: application/json" \
      -d "{\"instance_id\": \"${id}\"}" \
      "${api_base}/models/unload" 2>/dev/null || true
  done
}

# --- Fetch model list from LM Studio (native API: key and max_context_length) ---
# Output: one line per LLM: "key|max_context_length"
fetch_models_lmstudio() {
  local base_url="${1:-$LMSTUDIO_URL}"
  local api_base="${base_url}/api/v1"
  local resp
  resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${api_base}/models" 2>/dev/null) || true
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach LM Studio at ${base_url}. Is the local server running?" >&2
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

# --- Ollama: check server (GET /api/tags), list models ---
check_server_ollama() {
  local base_url="${1:-$OLLAMA_URL}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${base_url}/api/tags" 2>/dev/null) || true
  [[ "$code" == "200" ]]
}

fetch_models_ollama() {
  local base_url="${1:-$OLLAMA_URL}"
  local resp
  resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "${base_url}/api/tags" 2>/dev/null) || true
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach Ollama at ${base_url}. Is 'ollama serve' running?" >&2
    return 1
  fi
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.models[]?' &>/dev/null; then
      echo "$resp" | jq -r '.models[] | "\(.name)|32768"'
      return 0
    fi
  else
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('models', []):
        name = m.get('name', '')
        if name:
            print(name + '|32768')
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse model list from Ollama. Response: ${resp:0:200}" >&2
  return 1
}

# --- llama.cpp llama-server: OpenAI-compatible GET /v1/models (optional Bearer token) ---
check_server_llamacpp() {
  local base_url="$1" auth_token="${2:-}"
  local url="${base_url%/}/v1/models"
  local code
  if [[ -n "$auth_token" ]]; then
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$CURL_TIMEOUT" \
      -H "Authorization: Bearer ${auth_token}" "$url" 2>/dev/null) || true
  else
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null) || true
  fi
  [[ "$code" == "200" ]]
}

fetch_models_llamacpp() {
  local base_url="$1" auth_token="${2:-}"
  local url="${base_url%/}/v1/models"
  local resp
  if [[ -n "$auth_token" ]]; then
    resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" \
      -H "Authorization: Bearer ${auth_token}" "$url" 2>/dev/null) || true
  else
    resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null) || true
  fi
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach llama.cpp server at ${base_url}. Is llama-server running?" >&2
    return 1
  fi
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.data[]?' &>/dev/null; then
      echo "$resp" | jq -r '.data[] | "\(.id)|\(.context_length // .max_tokens // .max_context_tokens // .max_input_tokens // 32768)"'
      return 0
    fi
  else
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('data', []):
        mid = m.get('id', '')
        ctx = m.get('context_length') or m.get('max_tokens') or m.get('max_context_tokens') or m.get('max_input_tokens') or 32768
        if mid:
            print(str(mid) + '|' + str(ctx))
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse /v1/models from llama.cpp server. Response: ${resp:0:200}" >&2
  return 1
}

# OpenRouter model catalog is at GET https://openrouter.ai/api/v1/models; Claude Code base must be https://openrouter.ai/api (no /v1).
openrouter_models_list_url() {
  local b="${1%/}"
  if [[ "$b" == *"/api/v1" ]]; then
    echo "${b}/models"
  else
    echo "${b}/v1/models"
  fi
}

# --- OpenRouter: check (GET .../api/v1/models with Bearer), list models ---
check_server_openrouter() {
  local base_url="${1:-$OPENROUTER_URL}" api_key="$2"
  local tm="${CURL_TIMEOUT_CLOUD:-$CURL_TIMEOUT}"
  local list_url
  list_url=$(openrouter_models_list_url "$base_url")
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time "$tm" --retry 2 --retry-delay 1 \
    -H "Authorization: Bearer ${api_key}" "$list_url" 2>/dev/null) || true
  [[ "$code" == "200" ]]
}

fetch_models_openrouter() {
  local base_url="${1:-$OPENROUTER_URL}" api_key="$2"
  local tm="${CURL_TIMEOUT_CLOUD:-$CURL_TIMEOUT}"
  local list_url resp
  list_url=$(openrouter_models_list_url "$base_url")
  resp=$(curl -sS --connect-timeout 5 --max-time "$tm" --retry 2 --retry-delay 1 \
    -H "Authorization: Bearer ${api_key}" "$list_url" 2>/dev/null) || true
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach OpenRouter. Check API key and network." >&2
    return 1
  fi
  # Context/max tokens: use provider value when present; fallback 32768 when API does not advertise
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.data[]?' &>/dev/null; then
      echo "$resp" | jq -r '.data[] | "\(.id)|\(.context_length // .max_tokens // .max_context_tokens // .max_input_tokens // 32768)"'
      return 0
    fi
  else
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('data', []):
        mid = m.get('id', '')
        ctx = m.get('context_length') or m.get('max_tokens') or m.get('max_context_tokens') or m.get('max_input_tokens') or 32768
        if mid:
            print(str(mid) + '|' + str(ctx))
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse OpenRouter models. Response: ${resp:0:200}" >&2
  return 1
}

# True if response looks like OpenAI list-models with a non-empty .data array (works with or without jq).
custom_models_json_has_data() {
  local resp="$1"
  [[ -z "$resp" ]] && return 1
  if command -v jq &>/dev/null; then
    echo "$resp" | jq -e '.data | type == "array" and length > 0' &>/dev/null
    return $?
  fi
  echo "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    dd = d.get('data')
    sys.exit(0 if isinstance(dd, list) and len(dd) > 0 else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

# --- Custom (OpenAI-compatible): GET base/models or base/v1/models with Bearer ---
check_server_custom() {
  local base_url="$1" api_key="$2"
  local tm="${CURL_TIMEOUT_CLOUD:-$CURL_TIMEOUT}"
  local url="$base_url"
  [[ "$url" != */ ]] && url="${url}/"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time "$tm" --retry 2 --retry-delay 1 \
    -H "Authorization: Bearer ${api_key}" "${url}models" 2>/dev/null) || true
  if [[ "$code" == "200" ]]; then return 0; fi
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time "$tm" --retry 2 --retry-delay 1 \
    -H "Authorization: Bearer ${api_key}" "${url}v1/models" 2>/dev/null) || true
  [[ "$code" == "200" ]]
}

fetch_models_custom() {
  local base_url="$1" api_key="$2"
  local tm="${CURL_TIMEOUT_CLOUD:-$CURL_TIMEOUT}"
  local url="$base_url"
  [[ "$url" != */ ]] && url="${url}/"
  local resp
  resp=$(curl -sS --connect-timeout 5 --max-time "$tm" --retry 2 --retry-delay 1 \
    -H "Authorization: Bearer ${api_key}" "${url}models" 2>/dev/null) || true
  if ! custom_models_json_has_data "$resp"; then
    resp=$(curl -sS --connect-timeout 5 --max-time "$tm" --retry 2 --retry-delay 1 \
      -H "Authorization: Bearer ${api_key}" "${url}v1/models" 2>/dev/null) || true
  fi
  if [[ -z "${resp}" ]]; then
    echo "Error: Could not reach custom API at ${base_url}. Check URL and API key." >&2
    return 1
  fi
  # Context/max tokens: use provider value when present (context_length, max_tokens, etc.); fallback 32768 only when API does not advertise
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.data[]?' &>/dev/null; then
      echo "$resp" | jq -r '.data[] | "\(.id)|\(.context_length // .max_tokens // .max_context_tokens // .max_input_tokens // 32768)"'
      return 0
    fi
  else
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for m in d.get('data', []):
        mid = m.get('id', '')
        ctx = m.get('context_length') or m.get('max_tokens') or m.get('max_context_tokens') or m.get('max_input_tokens') or 32768
        if mid:
            print(str(mid) + '|' + str(ctx))
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse custom API model list. Response: ${resp:0:200}" >&2
  return 1
}

# --- NewAPI (QuantumNous unified gateway): GET /api/models, response data = { "channel_id": ["model1", ...] } ---
# Chat uses base_url/v1/chat/completions; we store root base_url and use base_url/v1 for Claude Code.
check_server_newapi() {
  local base_url="$1" api_key="$2"
  local url="${base_url%/}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time "$CURL_TIMEOUT" \
    -H "Authorization: Bearer ${api_key}" "${url}/api/models" 2>/dev/null) || true
  [[ "$code" == "200" ]]
}

fetch_models_newapi() {
  local base_url="$1" api_key="$2"
  local url="${base_url%/}"
  local resp
  resp=$(curl -s --connect-timeout 2 --max-time "$CURL_TIMEOUT" \
    -H "Authorization: Bearer ${api_key}" "${url}/api/models" 2>/dev/null) || true
  if [[ -z "$resp" ]]; then
    echo "Error: Could not reach NewAPI at ${base_url}. Check URL and API key." >&2
    return 1
  fi
  if command -v jq &>/dev/null; then
    if echo "$resp" | jq -e '.data | type == "object"' &>/dev/null; then
      echo "$resp" | jq -r '.data | to_entries[] | .value[]? // empty | "\(.)|32768"'
      return 0
    fi
  else
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data') or {}
    for channel_models in data.values() if isinstance(data, dict) else []:
        for m in channel_models if isinstance(channel_models, list) else []:
            if m:
                print(str(m) + '|32768')
except Exception:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  echo "Error: Could not parse NewAPI model list. Response: ${resp:0:200}" >&2
  return 1
}

# --- Unified: check server and fetch models by backend ---
check_server_for_backend() {
  case "$CURRENT_BACKEND" in
    lmstudio)  check_server_lmstudio "$CURRENT_BASE_URL" ;;
    ollama)    check_server_ollama "$CURRENT_BASE_URL" ;;
    llamacpp)  check_server_llamacpp "$CURRENT_BASE_URL" "$CURRENT_AUTH" ;;
    openrouter) check_server_openrouter "$CURRENT_BASE_URL" "$CURRENT_API_KEY" ;;
    custom)    check_server_custom "${CURRENT_CUSTOM_LIST_URL:-$CURRENT_BASE_URL}" "$CURRENT_API_KEY" ;;
    newapi)    check_server_newapi "$CURRENT_BASE_URL" "$CURRENT_API_KEY" ;;
    *)         check_server_lmstudio "$CURRENT_BASE_URL" ;;
  esac
}

fetch_models_for_backend() {
  case "$CURRENT_BACKEND" in
    lmstudio)  fetch_models_lmstudio "$CURRENT_BASE_URL" ;;
    ollama)    fetch_models_ollama "$CURRENT_BASE_URL" ;;
    llamacpp)  fetch_models_llamacpp "$CURRENT_BASE_URL" "$CURRENT_AUTH" ;;
    openrouter) fetch_models_openrouter "$CURRENT_BASE_URL" "$CURRENT_API_KEY" ;;
    custom)    fetch_models_custom "${CURRENT_CUSTOM_LIST_URL:-$CURRENT_BASE_URL}" "$CURRENT_API_KEY" ;;
    newapi)    fetch_models_newapi "$CURRENT_BASE_URL" "$CURRENT_API_KEY" ;;
    *)         fetch_models_lmstudio "$CURRENT_BASE_URL" ;;
  esac
}

# --- Interactive model selection (numbered menu); outputs "key|max_context_length" ---
# Uses fetch_models_for_backend (CURRENT_BACKEND, CURRENT_BASE_URL, CURRENT_API_KEY must be set).
select_model() {
  local keys=() max_ctx=()
  local line key ctx
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%|*}"
    ctx="${line##*|}"
    [[ -n "$key" ]] && keys+=("$key") && max_ctx+=("$ctx")
  done < <(fetch_models_for_backend)

  if [[ ${#keys[@]} -eq 0 ]]; then
    echo "No models found. Check that the backend is running and configured, then try again." >&2
    return 1
  fi

  local backend_label="$CURRENT_BACKEND"
  echo "Models available ($backend_label):" >&2
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
# Args: model_key, max_context_length. Optional third: current_ctx (when model already loaded).
# When current_ctx is set, option 1 is "Keep current (current_ctx)"; no reload if chosen.
# Outputs chosen context_length (number).
select_context_length() {
  local model_key="$1" max_ctx="$2" current_ctx="${3:-}"
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

  if [[ -n "$current_ctx" ]]; then
    echo "Model $model_key is already loaded with context length $current_ctx." >&2
    echo "Change context or keep as is?" >&2
    echo "" >&2
    echo "  1) Keep current ($current_ctx)" >&2
    echo "  2) $v1" >&2
    echo "  3) $v2" >&2
    echo "  4) $v3" >&2
    echo "  5) $v4" >&2
    echo "  6) $max_ctx" >&2
    echo "  7) Custom (enter your own number)" >&2
    echo "" >&2
    local choice
    while true; do
      read -rp "Choose (1-7): " choice
      case "$choice" in
        1) echo "$current_ctx"; return 0 ;;
        2) echo "$v1"; return 0 ;;
        3) echo "$v2"; return 0 ;;
        4) echo "$v3"; return 0 ;;
        5) echo "$v4"; return 0 ;;
        6) echo "$max_ctx"; return 0 ;;
        7)
          read -rp "Enter context length (${min_ctx}-${max_ctx}): " choice
          if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge "$min_ctx" ]] && [[ "$choice" -le "$max_ctx" ]]; then
            echo "$choice"
            return 0
          fi
          echo "Enter a number between $min_ctx and $max_ctx." >&2
          ;;
        *)
          echo "Invalid choice. Enter 1-7." >&2
          ;;
      esac
    done
  fi

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

# --- Memory check: system RAM and GPU VRAM (NVIDIA, AMD, Intel) ---
# Output: system RAM available in MB; GPU lines "vendor|free_mb|total_mb" (one per GPU).
get_system_ram_available_mb() {
  if [[ -r /proc/meminfo ]]; then
    local avail
    avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
    [[ -n "$avail" ]] && echo "$avail" && return 0
  fi
  echo "0"
  return 1
}

# Detect GPU(s) and output "vendor|free_mb|total_mb" per line. Vendor: NVIDIA, AMD, Intel, or unknown.
get_gpu_vram_info() {
  local card path vendor total_mb free_mb

  # NVIDIA: nvidia-smi (free + total per GPU)
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=memory.free,memory.total --format=csv,noheader,nounits 2>/dev/null | while IFS=, read -r free total; do
      free=$(echo "$free" | tr -d ' ')
      total=$(echo "$total" | tr -d ' ')
      [[ -n "$total" && "$total" -gt 0 ]] && echo "NVIDIA|${free}|${total}"
    done
    return 0
  fi

  # AMD / Intel: /sys/class/drm/card*/device/
  for card in /sys/class/drm/card[0-9]*/; do
    [[ -d "${card}device" ]] || continue
    path="${card}device"
    # Skip if no DRM device (e.g. output only)
    [[ -e "${path}/mem_info_vram_total" ]] || [[ -e "${path}/mem_info_vram_used" ]] || continue
    vendor="unknown"
    if [[ -f "${path}/vendor" ]]; then
      local v
      v=$(cat "${path}/vendor" 2>/dev/null)
      [[ "$v" == "0x1002" ]] && vendor="AMD"
      [[ "$v" == "0x8086" ]] && vendor="Intel"
      [[ "$v" == "0x10de" ]] && vendor="NVIDIA"
    fi
    # Prefer PCI device uevent for vendor (card's device is usually the PCI GPU)
    if [[ -f "${path}/uevent" ]]; then
      local pci_id
      pci_id=$(grep -E '^PCI_ID=' "${path}/uevent" 2>/dev/null | cut -d= -f2)
      case "$pci_id" in
        1002:*) vendor="AMD" ;;
        8086:*) vendor="Intel" ;;
        10de:*) vendor="NVIDIA" ;;
      esac
    fi
    total_mb=0
    free_mb=0
    if [[ -r "${path}/mem_info_vram_total" ]]; then
      total_mb=$(($(cat "${path}/mem_info_vram_total" 2>/dev/null || echo 0) / 1048576))
      if [[ -r "${path}/mem_info_vram_used" ]]; then
        local used
        used=$(($(cat "${path}/mem_info_vram_used" 2>/dev/null || echo 0) / 1048576))
        free_mb=$((total_mb - used))
        [[ $free_mb -lt 0 ]] && free_mb=0
      else
        free_mb="$total_mb"
      fi
    fi
    [[ "$total_mb" -gt 0 ]] && echo "${vendor}|${free_mb}|${total_mb}"
  done
  return 0
}

# Rough estimate: model size (from key e.g. 7b, 20b, 30b) + KV cache for context. Returns MB.
estimate_required_mb() {
  local model_key="$1" context="$2"
  local param_b=7
  if [[ "$model_key" =~ [0-9]+[bB] ]]; then
    param_b=$(echo "$model_key" | grep -oE '[0-9]+[bB]' | head -1 | tr -d bB)
    [[ -z "$param_b" || "$param_b" -lt 1 ]] && param_b=7
  fi
  # Model weights fp16: ~2 bytes per param -> param_b * 2 GB = param_b * 2048 MB
  local model_mb=$((param_b * 2048))
  # KV cache: conservative ~0.5 MB per token (varies by architecture)
  local cache_mb=$((context * 512 / 1024))
  echo $((model_mb + cache_mb))
}

# Check system RAM + GPU VRAM vs estimated need; if likely insufficient, warn and ask "Proceed anyway? [y/N]". Return 0 to proceed, 1 to abort.
check_memory_and_confirm() {
  local model_key="$1" context_length="$2"
  local ram_mb req_mb
  ram_mb=$(get_system_ram_available_mb)
  req_mb=$(estimate_required_mb "$model_key" "$context_length")

  local total_available_mb="$ram_mb"
  local gpu_lines=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    gpu_lines+=("$line")
    local free
    free=$(echo "$line" | cut -d'|' -f2)
    [[ -n "$free" && "$free" =~ ^[0-9]+$ ]] && total_available_mb=$((total_available_mb + free))
  done < <(get_gpu_vram_info)

  echo "" >&2
  echo "Memory check:" >&2
  echo "  System RAM available: ${ram_mb} MB" >&2
  for line in "${gpu_lines[@]}"; do
    local vendor free total
    IFS='|' read -r vendor free total <<< "$line"
    echo "  GPU ($vendor): ${free} MB free / ${total} MB total" >&2
  done
  if [[ ${#gpu_lines[@]} -eq 0 ]]; then
    echo "  GPU: none detected (using system RAM only)" >&2
  fi
  echo "  Estimated need for this model + context: ~${req_mb} MB" >&2
  
  # Calculate headroom and show hint
  local headroom=$(( total_available_mb - req_mb ))
  local headroom_pct=0
  if [[ "$total_available_mb" -gt 0 ]]; then
    headroom_pct=$(( (headroom * 100) / total_available_mb ))
  fi
  
  echo "" >&2

  if [[ "$total_available_mb" -ge "$req_mb" ]]; then
    if [[ "$headroom_pct" -lt 20 ]]; then
      echo "  HINT: Low memory headroom (${headroom_pct}%). Consider reducing context length." >&2
    else
      echo "  OK: sufficient memory detected with comfortable headroom for KV cache growth." >&2
    fi
    return 0
  fi

  echo "  NOTICE: Estimated need (~${req_mb} MB) exceeds available (~${total_available_mb} MB)." >&2
  echo "  Loading may fail (e.g. HTTP 500). Try a smaller context length if it does." >&2
  echo "" >&2
  local confirm
  read -rp "Proceed anyway? [y/N]: " confirm
  confirm="${confirm:-n}"
  [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] && return 0
  echo "Aborted. Run claudius again and choose a smaller context length." >&2
  return 1
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
# Unloads any currently loaded model(s) first to avoid load conflicts (e.g. HTTP 500).
# Args: model_key, context_length, api_base (e.g. http://localhost:1234/api/v1)
load_model_with_context() {
  local model_key="$1" context_length="$2" api_base="${3:-$LMSTUDIO_API}"
  local tmp resp body code
  unload_loaded_models "$api_base"
  tmp=$(mktemp)
  (
    curl -s -w "\n%{http_code}" --connect-timeout 2 --max-time 300 \
      -X POST -H "Content-Type: application/json" \
      -d "{\"model\": \"${model_key}\", \"context_length\": ${context_length}}" \
      "${api_base}/models/load" 2>/dev/null || printf '\n000\n'
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
# Args: model_id, base_url, auth_token, api_key, backend
# OpenRouter: ANTHROPIC_AUTH_TOKEN + ANTHROPIC_API_KEY "". Alibaba DashScope custom /apps/anthropic: same (v0.9.4 GitHub). Other custom|newapi: API_KEY only. lmstudio|ollama|llamacpp: AUTH_TOKEN (llamacpp adds extras).
write_settings() {
  local model_id="$1" base_url="${2:-http://localhost:1234}" auth_token="${3:-lmstudio}" api_key="${4:-}" backend="${5:-lmstudio}"
  [[ -z "$api_key" ]] && api_key="$auth_token"
  local show_turn dashscope_anthropic=0
  [[ "$backend" == "custom" && "$base_url" == *"dashscope"* && "$base_url" == *"/apps/anthropic"* ]] && dashscope_anthropic=1
  show_turn=$(get_show_turn_duration)
  local schema="https://json.schemastore.org/claude-code-settings.json"
  local tmp
  tmp=$(mktemp)
  case "$backend" in
    openrouter)
      if command -v jq &>/dev/null; then
        jq -n \
          --arg schema "$schema" \
          --arg base "$base_url" \
          --arg tok "$api_key" \
          --arg model "$model_id" \
          --arg show_turn "$show_turn" \
          '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_AUTH_TOKEN": $tok, "ANTHROPIC_API_KEY": ""}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
          > "$tmp"
      else
        python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_AUTH_TOKEN\": \"$api_key\",
        \"ANTHROPIC_API_KEY\": \"\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
      fi ;;
    custom)
      if [[ $dashscope_anthropic -eq 1 ]]; then
        if command -v jq &>/dev/null; then
          jq -n \
            --arg schema "$schema" \
            --arg base "$base_url" \
            --arg tok "$api_key" \
            --arg model "$model_id" \
            --arg show_turn "$show_turn" \
            '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_AUTH_TOKEN": $tok, "ANTHROPIC_API_KEY": ""}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
            > "$tmp"
        else
          python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_AUTH_TOKEN\": \"$api_key\",
        \"ANTHROPIC_API_KEY\": \"\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
        fi
      else
        if command -v jq &>/dev/null; then
          jq -n \
            --arg schema "$schema" \
            --arg base "$base_url" \
            --arg apik "$api_key" \
            --arg model "$model_id" \
            --arg show_turn "$show_turn" \
            '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_API_KEY": $apik}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
            > "$tmp"
        else
          python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_API_KEY\": \"$api_key\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
        fi
      fi ;;
    newapi)
      if command -v jq &>/dev/null; then
        jq -n \
          --arg schema "$schema" \
          --arg base "$base_url" \
          --arg apik "$api_key" \
          --arg model "$model_id" \
          --arg show_turn "$show_turn" \
          '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_API_KEY": $apik}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
          > "$tmp"
      else
        python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_API_KEY\": \"$api_key\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
      fi ;;
    llamacpp)
      if command -v jq &>/dev/null; then
        jq -n \
          --arg schema "$schema" \
          --arg base "$base_url" \
          --arg auth "$auth_token" \
          --arg model "$model_id" \
          --arg show_turn "$show_turn" \
          '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_AUTH_TOKEN": $auth, "ANTHROPIC_API_KEY": "", "CLAUDE_CODE_ATTRIBUTION_HEADER": "0", "ENABLE_TOOL_SEARCH": "true", "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "100000"}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
          > "$tmp"
      else
        python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_AUTH_TOKEN\": \"$auth_token\",
        \"ANTHROPIC_API_KEY\": \"\",
        \"CLAUDE_CODE_ATTRIBUTION_HEADER\": \"0\",
        \"ENABLE_TOOL_SEARCH\": \"true\",
        \"CLAUDE_CODE_AUTO_COMPACT_WINDOW\": \"100000\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
      fi ;;
    *)
      if command -v jq &>/dev/null; then
        jq -n \
          --arg schema "$schema" \
          --arg base "$base_url" \
          --arg auth "$auth_token" \
          --arg model "$model_id" \
          --arg show_turn "$show_turn" \
          '{"$schema": $schema, "env": {"ANTHROPIC_BASE_URL": $base, "ANTHROPIC_AUTH_TOKEN": $auth}, "defaultModel": $model, "showTurnDuration": ($show_turn == "true")}' \
          > "$tmp"
      else
        python3 -c "
import json
print(json.dumps({
    \"\$schema\": \"$schema\",
    \"env\": {
        \"ANTHROPIC_BASE_URL\": \"$base_url\",
        \"ANTHROPIC_AUTH_TOKEN\": \"$auth_token\"
    },
    \"defaultModel\": \"$model_id\",
    \"showTurnDuration\": ($show_turn == \"true\")
}, indent=2))
" > "$tmp"
      fi ;;
  esac
  mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
  mv "$tmp" "$CLAUDE_SETTINGS"
  echo "  Updated: $CLAUDE_SETTINGS (defaultModel = $model_id)"
}

# (update_shell_exports is defined earlier; use it with get_current_shell and CURRENT_* vars)

# --- Verify config and export env for this process ---
# Args: model_id, base_url, auth_token, api_key, backend
# OpenRouter: AUTH_TOKEN + empty API_KEY (official). Alibaba DashScope custom /apps/anthropic: same. Other custom|newapi: API_KEY. lmstudio|ollama: AUTH_TOKEN. llamacpp: same + compaction/tool-search.
verify_and_export() {
  local model_id="$1" base_url="${2:-http://localhost:1234}" auth_token="${3:-lmstudio}" api_key="${4:-}" backend="${5:-lmstudio}"
  local dashscope_anthropic=0
  [[ "$backend" == "custom" && "$base_url" == *"dashscope"* && "$base_url" == *"/apps/anthropic"* ]] && dashscope_anthropic=1
  [[ -z "$api_key" ]] && api_key="$auth_token"
  export ANTHROPIC_BASE_URL="$base_url"
  export CLAUDE_CODE_ATTRIBUTION_HEADER="0"
  case "$backend" in
    openrouter)
      unset -v ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
      unset -v ANTHROPIC_API_KEY 2>/dev/null || true
      export ANTHROPIC_AUTH_TOKEN="$api_key"
      export ANTHROPIC_API_KEY=""
      ;;
    custom)
      if [[ $dashscope_anthropic -eq 1 ]]; then
        unset -v ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
        unset -v ANTHROPIC_API_KEY 2>/dev/null || true
        export ANTHROPIC_AUTH_TOKEN="$api_key"
        export ANTHROPIC_API_KEY=""
      else
        unset -v ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
        export ANTHROPIC_API_KEY="$api_key"
      fi
      ;;
    newapi)
      unset -v ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
      export ANTHROPIC_API_KEY="$api_key"
      ;;
    llamacpp)
      unset -v ANTHROPIC_API_KEY 2>/dev/null || true
      export ANTHROPIC_API_KEY=""
      export ANTHROPIC_AUTH_TOKEN="$auth_token"
      export ENABLE_TOOL_SEARCH="true"
      export CLAUDE_CODE_AUTO_COMPACT_WINDOW="100000"
      ;;
    *)
      unset -v ANTHROPIC_API_KEY 2>/dev/null || true
      export ANTHROPIC_AUTH_TOKEN="$auth_token"
      ;;
  esac

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
  case "$backend" in
    openrouter)
      echo "  ANTHROPIC_AUTH_TOKEN=<set> (OpenRouter key)"
      echo "  ANTHROPIC_API_KEY=(empty)"
      ;;
    custom)
      if [[ $dashscope_anthropic -eq 1 ]]; then
        echo "  ANTHROPIC_AUTH_TOKEN=<set> (DashScope API key)"
        echo "  ANTHROPIC_API_KEY=(empty)"
      else
        echo "  ANTHROPIC_API_KEY=<set>"
      fi
      ;;
    newapi) echo "  ANTHROPIC_API_KEY=<set>" ;;
    llamacpp)
      echo "  ANTHROPIC_AUTH_TOKEN=<set>"
      echo "  ANTHROPIC_API_KEY=(empty)"
      echo "  ENABLE_TOOL_SEARCH=true"
      echo "  CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000"
      ;;
    *) echo "  ANTHROPIC_AUTH_TOKEN=<set>" ;;
  esac
  echo "  defaultModel (for this run)= $model_id"
  echo ""
}

# --- Post-setup instructions (print after config is written) ---
print_post_setup_instructions() {
  echo ""
  echo "Model is ready. You can:"
  echo "  1) Start Claude Code in this terminal now (choose below)"
  echo "  2) Use Claude in VS Code / Cursor: set claudeCode.environmentVariables to ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN (or ANTHROPIC_API_KEY) from the config we wrote."
  echo "  3) Use in Forks or other IDEs: same env vars in your Claude Code integration."
  echo ""
}

# --- Main ---
main() {
  local dry_run=0 bypass_start=0 last_mode=0
  [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && print_help && exit 0

  for a in "$@"; do
    [[ "$a" == "--by-pass-start" ]] && bypass_start=1
    [[ "$a" == "--last" ]] && last_mode=1
  done

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
    # First-time run: check dependencies before setup
    echo "First-time run: checking dependencies..."
    echo ""
    if ! check_required_commands; then
      exit 1
    fi
    run_init
    # Backend-specific check after we have prefs
    local init_backend
    init_backend=$(get_pref "backend")
    case "$init_backend" in
      lmstudio) check_lm_studio_installed || exit 1 ;;
      ollama)   check_ollama_installed || exit 1 ;;
      *)        ;;
    esac
  fi

  resolve_backend

  if [[ "$dry_run" -eq 0 ]] && ! ensure_claude_installed; then
    echo "Claude Code CLI is required. Install it, then run claudius again."
    exit 1
  fi

  local platform
  platform=$(detect_platform)
  echo "Claudius v${VERSION} - Claude Code multi-backend (${CURRENT_BACKEND})"
  echo "Backend: $CURRENT_BACKEND @ $CURRENT_BASE_URL"
  [[ "$dry_run" -eq 1 ]] && echo "(dry-run: will not write config or start claude)"
  echo ""

  until check_server_for_backend; do
    wait_for_server
  done

  local model_id max_ctx context_length skip_load=0
  local api_base="${CURRENT_BASE_URL}/api/v1"

  if [[ "$last_mode" -eq 1 ]]; then
    model_id=$(get_pref "lastModel")
    context_length=$(get_pref "lastContextLength")
    [[ -z "$context_length" || ! "$context_length" =~ ^[0-9]+$ ]] && context_length=32768
    if [[ -z "$model_id" ]]; then
      echo "No last model saved. Run claudius once to select a model."
      exit 1
    fi
    max_ctx="$context_length"
    echo ""
    echo "Using last: $model_id (context length $context_length)"
    echo ""
    if [[ "$CURRENT_BACKEND" == "lmstudio" ]]; then
      local loaded_line loaded_key current_ctx
      loaded_line=$(get_loaded_lmstudio_model "$api_base" 2>/dev/null) || true
      if [[ -n "$loaded_line" ]]; then
        loaded_key="${loaded_line%%|*}"
        current_ctx="${loaded_line##*|}"
        if [[ "$loaded_key" == "$model_id" && "$current_ctx" == "$context_length" ]]; then
          skip_load=1
        fi
      fi
    fi
  else
    local model_line
    model_line=$(select_model) || exit 1
    model_id="${model_line%%|*}"
    max_ctx="${model_line##*|}"
    echo ""
    echo "Selected: $model_id (max $max_ctx tokens)"
    echo ""
    if [[ "$CURRENT_BACKEND" == "lmstudio" ]]; then
      local loaded_line loaded_key current_ctx
      loaded_line=$(get_loaded_lmstudio_model "$api_base" 2>/dev/null) || true
      if [[ -n "$loaded_line" ]]; then
        loaded_key="${loaded_line%%|*}"
        current_ctx="${loaded_line##*|}"
        if [[ "$loaded_key" == "$model_id" ]]; then
          context_length=$(select_context_length "$model_id" "$max_ctx" "$current_ctx") || exit 1
          if [[ "$context_length" == "$current_ctx" ]]; then
            skip_load=1
          fi
        else
          context_length=$(select_context_length "$model_id" "$max_ctx") || exit 1
        fi
      else
        context_length=$(select_context_length "$model_id" "$max_ctx") || exit 1
      fi
      echo ""
      echo "Context length: $context_length"
      echo ""
    else
      context_length="$max_ctx"
    fi
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[dry-run] Would configure $model_id, write $CLAUDE_SETTINGS, run: claude --model $model_id"
    exit 0
  fi

  if [[ "$CURRENT_BACKEND" == "lmstudio" ]]; then
    if [[ "$skip_load" -eq 1 ]]; then
      echo "  Using already-loaded model $model_id with context length $context_length (no reload)."
    else
      check_memory_and_confirm "$model_id" "$context_length" || exit 1
      echo "Loading model in LM Studio..."
      if ! load_model_with_context "$model_id" "$context_length" "$api_base"; then
        echo ""
        echo "Model load failed. Check LM Studio server logs (e.g. out of memory, missing file)."
        echo "Fix the issue and run claudius again, or choose another model/context length."
        exit 1
      fi
    fi
  else
    echo "  Using model: $model_id (no load step for $CURRENT_BACKEND)."
  fi

  local effective_base="$CURRENT_BASE_URL"
  if [[ "$CURRENT_BACKEND" == "newapi" ]]; then
    effective_base="${CURRENT_BASE_URL%/}/v1"
  fi
  save_last_model_prefs "$model_id" "$context_length"
  echo "Writing config..."
  write_settings "$model_id" "$effective_base" "$CURRENT_AUTH" "$CURRENT_API_KEY" "$CURRENT_BACKEND"
  local current_shell
  current_shell=$(get_current_shell)
  update_shell_exports "$current_shell" "$effective_base" "$CURRENT_AUTH" "$CURRENT_API_KEY" "$CURRENT_BACKEND"
  ensure_path_for_claude_in_shell_config "$current_shell"
  ensure_claudius_alias_in_shell_config "$current_shell"
  verify_and_export "$model_id" "$effective_base" "$CURRENT_AUTH" "$CURRENT_API_KEY" "$CURRENT_BACKEND"

  print_post_setup_instructions

  if [[ "$bypass_start" -eq 1 ]]; then
    echo "Config written. Run 'claude --model $model_id' when ready, or call the bootstrapper from your script."
    exit 0
  fi

  local start_now="y"
  if [[ "$last_mode" -eq 0 ]]; then
    read -rp "Start Claude Code in this terminal now? [Y/n]: " start_now
    start_now="${start_now:-y}"
  fi
  if [[ "${start_now,,}" != "n" && "${start_now,,}" != "no" ]]; then
    # Prefer ~/.local/bin (official Claude Code install location) so we see it even if PATH was not loaded in this session
    [[ -d "${HOME}/.local/bin" ]] && export PATH="${HOME}/.local/bin:${PATH}"
    if ! command -v claude &>/dev/null; then
      echo ""
      echo "Claude Code CLI (claude) is not installed or not in your PATH."
      echo ""
      local install_choice="n"
      read -rp "Install Claude Code now? [y/N]: " install_choice
      install_choice="${install_choice:-n}"
      if [[ "${install_choice,,}" == "y" || "${install_choice,,}" == "yes" ]]; then
        if try_install_claude_code; then
          : # claude is now in PATH, continue to start
        else
          exit 1
        fi
      else
        echo "  Install from: https://code.claude.com/docs"
        echo "  Then run: claude --model $model_id"
        echo "  Your config is in ~/.claude/settings.json; you can also use VS Code / Cursor with the same env vars."
        echo ""
        exit 1
      fi
    fi
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
  else
    echo "Skipped. Run 'claude --model $model_id' when ready, or use VS Code / Cursor / Forks with the same env vars."
  fi
}

main "$@"