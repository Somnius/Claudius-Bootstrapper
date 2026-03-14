# Claudius-Bootstrapper

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Claudius is a multi-backend bootstrapper for [Claude Code](https://code.claude.com/) (Anthropic’s agentic CLI). It connects Claude Code to **LM Studio**, **Ollama**, **OpenRouter**, or a **custom OpenAI-compatible API** (e.g. Alibaba Cloud Qwen). Supports Linux, macOS, and Windows (Git Bash/WSL). Writes env vars to your shell config (bash, zsh, fish, ksh, sh) automatically.

**Author:** Lefteris Iliadis ([Somnius](https://github.com/Somnius))  
**License:** [MIT](LICENSE)

---

## What it does

Claudius lets you choose a backend, pick a model, and run Claude Code against it. It writes `~/.claude/settings.json` and appends the correct env vars to your **shell config** (detected from `$SHELL`: bash → `.bashrc`, zsh → `.zshrc`, fish → `~/.config/fish/config.fish`, ksh/sh → `.kshrc`/`.profile`).

| Feature | Description |
|--------|-------------|
| **Backends** | **LM Studio** (local), **Ollama** (local), **OpenRouter** (cloud, API key), **Custom** (e.g. Alibaba Cloud — base URL + API key). Choose once at setup or with `claudius --init`. |
| **First-time / `--init`** | Asks: show reply duration, keep session on exit, and **which backend** (1–4). Saves to `~/.claude/claudius-prefs.json`. For OpenRouter/Custom, prompts for API key (and custom URL). |
| **Platform & deps** | Detects Linux/macOS/Windows and prints install hints for curl, jq, claude (e.g. apt/dnf/pacman on Linux, brew on macOS). Does not auto-install packages. |
| **Server check** | Verifies backend is reachable; for LM Studio/Ollama offers Resume / Start server / Abort; for OpenRouter/Custom offers Retry / Abort. |
| **Model list** | Fetches models from the chosen backend (LM Studio native API, Ollama `/api/tags`, OpenRouter/Custom `GET /models` with Bearer). Numbered menu to pick one. |
| **Context length** | **LM Studio only:** pick context size, then script unloads current model and loads the selected one with that length (spinner). Ollama/OpenRouter/Custom: no load step; model is used as-is. |
| **Memory check** | **LM Studio only:** checks RAM/VRAM before load and warns if insufficient. |
| **Config & shell** | Writes `~/.claude/settings.json` (base URL, auth, defaultModel) and appends ANTHROPIC_* exports to the **correct config file** for your shell (bash/zsh/fish/ksh/sh) with the right syntax (e.g. `set -gx` for fish). |
| **Post-setup** | Prints instructions: use Claude in this terminal, or in VS Code/Cursor/Forks with the same env vars. Asks “Start Claude Code now? [Y/n]”. |
| **Session on exit** | If you chose not to keep session history, after Claude Code exits you get a menu: delete current session, purge all (2 confirmations), or purge by age. |
| **`--purge`** | Interactive menu to purge saved session data. Settings and Claudius prefs are never removed. |
| **`--dry-run` / `--test`** | Run server check and model selection without writing config or starting Claude. |

---

## Backends

| Backend | Base URL (default) | Auth | Notes |
|---------|--------------------|------|------|
| **LM Studio** | `http://localhost:1234` | None (placeholder token) | Local; list/load via native API; context length and memory check. |
| **Ollama** | `http://localhost:11434` | None | Local; list via `/api/tags`; no load step (model used on first request). |
| **OpenRouter** | `https://openrouter.ai/api/v1` | API key (Bearer) | Cloud; list via `/models`; prompt for key at setup. |
| **Custom** | User-provided (e.g. Alibaba `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`) | API key (Bearer) | OpenAI-compatible `GET .../models`; list and pick model (e.g. qwen-max, qwen3.5-9b). |

Override with env: `CLAUDIUS_BACKEND`, `CLAUDIUS_BASE_URL`, `CLAUDIUS_API_KEY`, `LMSTUDIO_URL`, `OLLAMA_URL`, `OPENROUTER_URL`.

---

## Prerequisites

- [Claude Code](https://code.claude.com/) CLI on your PATH.
- `curl`, and either `jq` or Python 3 for JSON.
- **Per backend:** LM Studio (and `lms`) or Ollama (`ollama`) for local; API key for OpenRouter/Custom. Script prints install hints per platform (Linux/macOS/Windows).

---

## Installing the tools (for new visitors)

You need **Claude Code** (the CLI) and at least one **backend**. The script will prompt for missing tools and show install commands for your platform.

### 1. Install Claude Code

Go to **[code.claude.com/docs](https://code.claude.com/docs)** and follow the install instructions for your platform. Confirm with: `claude --version`.

### 2. Install a backend (pick one or more)

- **LM Studio:** [lmstudio.ai](https://lmstudio.ai/) — install, download a model, start Local Inference Server (port 1234) or run `lms server start`.
- **Ollama:** [ollama.com](https://ollama.com) — install, then run `ollama serve` (and pull models with `ollama pull <name>`).
- **OpenRouter:** [openrouter.ai](https://openrouter.ai) — create an API key; Claudius will prompt for it at setup.
- **Custom (e.g. Alibaba):** Use your provider’s base URL and API key; Claudius will prompt at setup.

### 3. Clone and use Claudius

```bash
git clone https://github.com/Somnius/Claudius-Bootstrapper.git ~/dev/Claudius-Bootstrapper
```

Add the alias for your shell (see [SHELL-SETUP.md](SHELL-SETUP.md)), then run `claudius`. On first run you choose backend and preferences; then pick a model and (for LM Studio) context length. Claudius appends env vars to the **correct config file** for your shell (bash/zsh/fish/ksh/sh).

---

## Usage

Set up the alias (see [SHELL-SETUP.md](SHELL-SETUP.md)) so `claudius` runs the script, or call the script by path.

### Run Claudius (normal flow)

```bash
claudius
```

Start your backend first if local (LM Studio or Ollama); for OpenRouter/Custom ensure your API key is set (in prefs or env). Then: choose model → for LM Studio only, choose context length and wait for load → script writes config and asks “Start Claude Code now? [Y/n]”. If you chose not to keep session history, after you exit Claude Code you get a menu to delete the current session, purge by age, or skip.

### Reset preferences (first-time questions again)

```bash
claudius --init
```

Re-asks: show reply duration, keep session history on exit, and **which backend** (1–4). Saves to `~/.claude/claudius-prefs.json`.  
If the script reported missing dependencies (required commands or backend app), install them, then run `claudius --init` to continue.

### Purge saved session data

```bash
claudius --purge
```

Interactive menu: purge all (with two confirmation prompts), purge last session only (last ~2 min), or purge by age (yesterday and back, 6h, 3h, 2h, 1h, 30 min). Does not remove `settings.json` or `claudius-prefs.json`.

### Test run (no config write, no Claude)

```bash
claudius --dry-run
# or
claudius --test
```

Runs server check, model selection, and context-length choice, then exits without writing config or starting Claude Code.

### Override backend via environment

```bash
# Use a specific backend and (for custom/openrouter) URL and key
CLAUDIUS_BACKEND=ollama claudius
CLAUDIUS_BACKEND=custom CLAUDIUS_BASE_URL=https://dashscope-intl.aliyuncs.com/compatible-mode/v1 CLAUDIUS_API_KEY=sk-xxx claudius

# Override default URLs per backend
LMSTUDIO_URL=http://127.0.0.1:1234 claudius
OLLAMA_URL=http://127.0.0.1:11434 claudius
```

### Using Claude Code in VS Code (chat panel)

Claudius runs the **CLI** in the terminal. To use the **Claude Code extension** in VS Code (chat panel, Spark icon) with the **same** backend: install the [Claude Code extension](https://marketplace.visualstudio.com/items?itemName=Anthropic.claude-code), then in VS Code **user settings** (JSON) set the same env vars Claudius wrote to your shell (from `~/.claude/settings.json`):

```json
"claudeCode.environmentVariables": [
  { "name": "ANTHROPIC_BASE_URL", "value": "http://localhost:1234" },
  { "name": "ANTHROPIC_AUTH_TOKEN", "value": "lmstudio" }
]
```

For LM Studio use `lmstudio` as token; for OpenRouter/Custom use your API key in `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY`. Set the extension’s default model to your chosen model ID. For MCP and a full step-by-step, see the extension docs or `GUIDE-VSCODE-CLAUDE-CHAT.md` if present (gitignored).

## Alias

In `~/.bashrc` (adjust path if you cloned elsewhere):

```bash
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

Then `source ~/.bashrc` or open a new shell. For **zsh**, **fish**, **ksh**, and **sh**, see [SHELL-SETUP.md](SHELL-SETUP.md).

## Configuration

| What          | Where                     |
|---------------|----------------------------|
| Base URL, auth, default model | `~/.claude/settings.json`  |
| Claudius prefs (backend, baseUrl, apiKey, turn duration, keep session) | `~/.claude/claudius-prefs.json` (first run or `claudius --init`) |
| Claude Code session data (purge with `claudius --purge`) | `~/.claude/projects`, `debug`, `file-history`, `history.jsonl`, etc. |
| Shell exports | **Auto-appended** to the right file for your shell (see [SHELL-SETUP.md](SHELL-SETUP.md)): `.bashrc`, `.zshrc`, `~/.config/fish/config.fish`, `.kshrc`/`.profile` |
| Default model | `defaultModel` in settings |

**Multi-shell:** Claudius detects your shell (`$SHELL` or `$CLAUDIUS_SHELL`) and appends ANTHROPIC_* vars with the correct syntax (e.g. `set -gx` for fish). **Env overrides:** `CLAUDIUS_BACKEND`, `CLAUDIUS_BASE_URL`, `CLAUDIUS_API_KEY`, `LMSTUDIO_URL`, `OLLAMA_URL`, `OPENROUTER_URL`. **Testing:** `claudius --dry-run` (or `--test`) runs server check and model selection without writing config or starting Claude.

## Changelog

- **0.8.0** (2026-03-14) – **Multi-backend and multi-shell refactor:** Backends: LM Studio, Ollama, OpenRouter, custom API (e.g. Alibaba Cloud). Choose backend at setup or via `CLAUDIUS_BACKEND`; custom/OpenRouter use base URL and API key. Platform detection (Linux/macOS/Windows) with per-OS install hints for curl/jq/claude. Shell-aware config: appends env vars to the correct file (bash/zsh/fish/ksh/sh) with correct syntax (`set -gx` for fish). Post-setup instructions (VS Code/Cursor/Forks) and “Start Claude Code now? [Y/n]”. No load step for Ollama/OpenRouter/Custom; context and memory check only for LM Studio.
- **0.7.1** (2026-03-07) – **New: `--help` command** and **Enhanced memory headroom hints**: Display helpful usage information with `claudius --help` or `-h`. Improved model status display when server is not running (shows currently loaded model ID). Enhanced memory check now shows comfortable vs low headroom hints (warns below 20% remaining for KV cache growth). Version bumped to 0.7.1.
- **0.7.0** (2026-03-07) – **VS Code chat panel integration**: Add guide and documentation for using the Claude Code extension in VS Code's chat UI with LM Studio backend, including MCP setup and model features (visual thinking). Update `.gitignore` to exclude optional local docs (`GUIDE-VSCODE-CLAUDE-CHAT.md`, `CLAUDE.md`, `discussion-log.md`).
- **0.6.2** (2026-03-01) – **`--purge`**: add option “Purge last session only” (last ~2 min). Fix showTurnDuration/keepSessionOnExit: prefs read now outputs lowercase `true`/`false` so `settings.json` gets the correct value (fixes “Cooked for X” not showing when user chose yes). README: troubleshooting for Cursor/VS Code opening extra windows when starting Claude Code.
- **0.6.1** (2026-03-01) – Before loading the selected model, unload any currently loaded model(s) in LM Studio via `/api/v1/models/unload` to avoid load conflicts and HTTP 500 when switching model or context.
- **0.6.0** (2026-03-01) – First-time dependency check: on first run (no `claudius-prefs.json`), script checks that LM Studio is installed (e.g. `lms` in PATH) and that required commands (curl, jq or python3, claude) are present. If anything is missing, prints where to download LM Studio and distro-specific install hints for the tools, then tells the user to install and run again with `claudius --init`.
- **0.5.2** (2026-03-01) – Memory check before load: reads system RAM and GPU VRAM (NVIDIA via `nvidia-smi`, AMD/Intel via sysfs). If estimated need (model + context) exceeds available memory, shows a notice and “Proceed anyway? [y/N]” to reduce accidental HTTP 500 load failures.
- **0.5.1** (2026-03-01) – When “don’t keep session” is set: after Claude Code exits, show a menu to delete current session only, purge all (2 confirmations), purge by age (yesterday, 6h, 3h, 2h, 1h, 30 min), or skip. README: “What it does” as feature table; Usage lists each command/option with examples.
- **0.5.0** (2026-03-01) – Session options: first-run asks whether to keep session history when Claude Code exits; if not, session data from that run is cleared after exit. **`claudius --purge`**: interactive menu to purge saved session data — purge all (with 2 confirmations), or by age (yesterday and back, 6h, 3h, 2h, 1h, 30 min). Settings and Claudius prefs are never purged.
- **0.4.2** (2026-03-01) – First-time setup: ask whether to show reply duration, save to `~/.claude/claudius-prefs.json`; `claudius --init` re-runs these questions. If model load fails (e.g. HTTP 500), script exits and does not start Claude; user is told to check LM Studio logs.
- **0.4.1** (2026-03-01) – After setting context length, wait for model load to finish with a spinner; show load time when returned by API. Then start Claude.
- **0.4.0** (2026-03-01) – Context length: script reads model max from LM Studio API, suggests 5 values + custom, loads model with chosen context via `POST /api/v1/models/load`. Numbered menus only (fzf/gum removed). Uses native API `/api/v1/models` for listing.
- **0.3.3** (2026-03-01) – README: project files table, config section references SHELL-SETUP.md and settings.json.example.
- **0.3.2** (2026-03-01) – Server-down menu uses gum or fzf when available; `settings.json.example` template; README config note.
- **0.3.1** (2026-03-01) – Model list fixed (menu to stderr). Optional fzf/gum for model selection. Version and author in script. README, LICENSE, .gitignore for public repo.
- **0.3.0** – Rename project to Claudius; script to `claudius.sh`; add `claudius` alias in `.bashrc`.
- **0.2.x** – Server check with Resume/Start/Abort; fetch models from LM Studio; interactive model choice; write `~/.claude/settings.json` and `.bashrc` exports; run Claude Code direct to LM Studio.
- **0.2.0** – Direct LM Studio (Anthropic-compatible API); base URL fix (no double `/v1`); remove LiteLLM proxy.
- **0.1.x** – LiteLLM proxy path fixes, venv and launcher fixes for moved `~/scripts/claude/` layout.
- **0.1.0** – Initial bootstrapper: LM Studio + Claude Code via proxy; env and model selection.

## Project files

| File                    | Description                                                |
|-------------------------|------------------------------------------------------------|
| `claudius.sh`           | Bootstrapper script                                        |
| [SHELL-SETUP.md](SHELL-SETUP.md) | How to add the `claudius` alias on **bash**, **zsh**, **fish**, **ksh**, and **sh** |
| [settings.json.example](settings.json.example) | Example `~/.claude/settings.json` (LM Studio). Base URL and auth depend on backend; Claudius writes this when you pick a model. |
| `README.md`             | This file                                                  |
| `LICENSE`               | MIT license                                                |
| `.gitignore`            | Ignore notes, local/sensitive; also `CLAUDE.md`, `GUIDE-VSCODE-CLAUDE-CHAT.md`, `discussion-log.md` |

Optional local docs (gitignored, not in the repo by default): `GUIDE-VSCODE-CLAUDE-CHAT.md` (step-by-step: Claude Code in VS Code chat panel + LM Studio + MCP), `CLAUDE.md` (project-specific Claude instructions), `discussion-log.md` (session notes and decisions).

## Troubleshooting

- **First run: “Missing required command(s)” or backend not installed** – Install the missing tools (script prints platform-specific hints: curl, jq, claude). For LM Studio install from https://lmstudio.ai; for Ollama from https://ollama.com. Then run `claudius --init` to continue.
- **Server not running** – For LM Studio: start Local Inference Server or run `lms server start`. For Ollama: run `ollama serve`. Then choose 1 (Resume). For OpenRouter/Custom: check API key and network, then Retry.
- **Memory check / “Proceed anyway?”** – The script estimates RAM + VRAM need from model size and context length. If you see the notice, try a smaller context length (e.g. 2048 or 34304) to avoid LM Studio load failures. GPU detection: NVIDIA uses `nvidia-smi`; AMD and Intel (including Arc) use `/sys/class/drm` when the driver exposes VRAM info; if no GPU is detected, only system RAM is considered.
- **`lms` not found** – Add LM Studio’s CLI to PATH (e.g. `~/.lmstudio/bin`) or start the server from the GUI.
- **No models** – LM Studio: load at least one model and ensure the server is running. Ollama: run `ollama pull <name>` and ensure `ollama serve` is running. OpenRouter/Custom: check API key and base URL; the provider’s `GET .../models` must return a list.
- **Model load failed (HTTP 500)** – LM Studio could not load the model (e.g. out of memory, corrupt file, unsupported config). The script unloads any previously loaded model before loading; if it still fails, check **LM Studio server logs** for the exact error, try a smaller context length or another model. The script no longer continues to start Claude when load fails.
- **`claudius` not found** – Run `source ~/.bashrc` or open a new terminal.
- **Slow or no response** – Curl uses a 10s timeout (`CURL_TIMEOUT`); load can take up to 300s. Use `claudius --dry-run` to test.
- **Cursor (or VS Code) opens extra windows when starting Claude Code** – This comes from **Claude Code’s IDE integration**, not from Claudius. When the Claude Code extension is installed, starting the CLI (e.g. via `claudius`) can trigger the IDE to open panels or new windows. **Workaround:** run `claudius` from a terminal **outside** Cursor (e.g. a standalone terminal like GNOME Terminal, kitty, Alacritty). Alternatively, disable the Claude Code extension in Cursor when you only want terminal-only use. See [anthropics/claude-code#18205](https://github.com/anthropics/claude-code/issues/18205), [#8768](https://github.com/anthropics/claude-code/issues/8768).
- **Base URL** – LM Studio: use `http://localhost:1234` with no trailing `/v1`; the script does this. For custom backends, use the provider’s full base URL (e.g. Alibaba compatible-mode URL).
- **OpenRouter / Custom: “Cannot reach” or empty model list** – Check API key (and for custom, base URL). Ensure no trailing slash on base URL unless the provider requires it.

## Thanks & links

Claudius relies on these tools; thanks to their authors and communities.

| Tool | Purpose |
|------|---------|
| [Claude Code](https://code.claude.com/) (Anthropic) | Agentic CLI that talks to the model |
| [LM Studio](https://lmstudio.ai/) | Local inference — [API](https://lmstudio.ai/docs/api/endpoints/rest), [CLI](https://lmstudio.ai/docs/cli) |
| [Ollama](https://ollama.com) | Local inference — `/api/tags` for model list |
| [OpenRouter](https://openrouter.ai) | Cloud API — many models, Bearer auth |
| **curl** | HTTP requests (list models, load for LM Studio) |
| **jq** or **Python 3** | JSON parsing of model list |
| **Bash** | Script runtime |

---
