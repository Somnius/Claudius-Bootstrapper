# Claudius-Bootstrapper

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Claudius is a multi-backend bootstrapper for [Claude Code](https://code.claude.com/) (Anthropic’s agentic CLI). It connects Claude Code to **LM Studio**, **Ollama**, **llama.cpp** (`llama-server`), **OpenRouter**, **Custom** (e.g. Alibaba DashScope, Kimi, DeepSeek), or **NewAPI**. Supports Linux, macOS, and Windows (Git Bash/WSL). Writes env vars to your shell config (bash, zsh, fish, ksh, sh) automatically.

**Author:** Lefteris Iliadis ([Somnius](https://github.com/Somnius))  
**License:** [MIT](LICENSE)

---

## What it does

Claudius lets you choose a backend, pick a model, and run Claude Code against it. It writes `~/.claude/settings.json` and appends the correct env vars to your **shell config** (detected from `$SHELL`: bash → `.bashrc`, zsh → `.zshrc`, fish → `~/.config/fish/config.fish`, ksh/sh → `.kshrc`/`.profile`).

| Feature | Description |
|--------|-------------|
| **Backends** | **LM Studio**, **Ollama**, **OpenRouter**, **Custom**, **NewAPI**, **llama.cpp server**. Custom presets: Alibaba (DashScope), Kimi, DeepSeek, Groq, OpenRouter, xAI, OpenAI, or Other. NewAPI: [QuantumNous new-api](https://github.com/QuantumNous/new-api). **llama.cpp:** `llama-server` (local or remote). Choose once at setup or with `claudius --init`. |
| **First-time / `--init`** | Asks: show reply duration, keep session on exit, and **which backend** (1–6). Saves to `~/.claude/claudius-prefs.json`. For OpenRouter/Custom/NewAPI/llama.cpp, prompts for API key or token and URL where needed. |
| **Platform & deps** | Detects Linux/macOS/Windows and prints install hints for curl, jq, claude (e.g. apt/dnf/pacman on Linux, brew on macOS). Does not auto-install packages. |
| **Server check** | LM Studio/Ollama: Resume / Start local / **Remote** / Abort. **llama.cpp:** Resume / Remote / Abort. OpenRouter/Custom/NewAPI: Retry / Abort. Remote: LM Studio (1234), Ollama (11434), or llama.cpp (8080). |
| **Model list** | LM Studio native API, Ollama `/api/tags`, OpenRouter/Custom Bearer `GET …/models`, NewAPI `GET /api/models`, llama.cpp `GET …/v1/models`. **Alibaba (intl.):** listing uses OpenAI-compatible `compatible-mode/v1`; config uses Anthropic `apps/anthropic` (see [Backends](#backends)). |
| **Context length** | **LM Studio only:** loaded-model keep/change, then load with chosen context. Other backends: no load step. |
| **Memory check** | **LM Studio only:** checks RAM/VRAM before load and warns if insufficient. |
| **Config & shell** | Writes `~/.claude/settings.json` (base URL, auth, defaultModel) and appends ANTHROPIC_* to your shell config. Ensures Claude Code CLI is installed (offers install if missing); after setup appends \`~/.local/bin\` to PATH and the **claudius** alias so \`claude\` and \`claudius\` work in new terminals. For **custom/OpenRouter/NewAPI** only `ANTHROPIC_API_KEY` is set; for **LM Studio/Ollama/llama.cpp** only `ANTHROPIC_AUTH_TOKEN` (llama.cpp also sets tool-search and compaction defaults). Claude Code never sees both token and API key (avoids “auth conflict”). |
| **Post-setup** | Prints instructions and asks "Start Claude Code now? [Y/n]". CLI is checked earlier; install is offered if missing. |
| **Session on exit** | If you chose not to keep session history, after Claude Code exits you get a menu: delete current session, purge all (2 confirmations), or purge by age. |
| **`--purge`** | Interactive menu to purge saved session data. Settings and Claudius prefs are never removed. |
| **`--dry-run` / `--test`** | Run server check and model selection without writing config or starting Claude. |
| **`--by-pass-start`** | Run full setup (model, config write) but do not ask to start Claude Code; exit after writing config (for use in scripts). |
| **`--last`** | Use last base URL, model, and context length; skip model menu and start Claude Code. Run `claudius` once to save a “last” choice. |

---

## Backends

| Backend | Base URL (default) | Auth | Notes |
|---------|--------------------|------|------|
| **LM Studio** | `http://localhost:1234` | None (placeholder token) | Local; list/load via native API; context length and memory check. |
| **Ollama** | `http://localhost:11434` | None | Local; list via `/api/tags`; no load step (model used on first request). |
| **OpenRouter** | `https://openrouter.ai/api/v1` | API key (Bearer) | Cloud; list via `/models`; prompt for key at setup. |
| **Custom** | Preset or user URL | API key (Bearer) | Presets: **Alibaba (DashScope, Singapore/intl.)**, **Kimi**, **DeepSeek**, **Groq**, **OpenRouter**, **xAI**, **OpenAI**, or **Other**. **Alibaba:** Claude Code needs the [Anthropic-compatible base](https://www.alibabacloud.com/help/en/model-studio/anthropic-api-messages) `https://dashscope-intl.aliyuncs.com/apps/anthropic` (not `…/compatible-mode/v1`). Claudius lists models via the OpenAI-compatible `…/compatible-mode/v1` endpoint automatically. |
| **NewAPI** | User (e.g. `http://localhost:8080`) | API key (Bearer) | [QuantumNous new-api](https://github.com/QuantumNous/new-api) unified gateway. Root URL in prefs; Claude Code uses `base/v1`. Model list from `GET /api/models`. |
| **llama.cpp** | `http://127.0.0.1:8080` (default) | Bearer (default `lmstudio`) | `llama-server` OpenAI-compatible `/v1`; optional local/remote; defaults include `ENABLE_TOOL_SEARCH` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` for Claude Code. |

Override with env: `CLAUDIUS_BACKEND`, `CLAUDIUS_BASE_URL`, `CLAUDIUS_API_KEY`, `CLAUDIUS_AUTH_TOKEN` (llama.cpp), `LMSTUDIO_URL`, `OLLAMA_URL`, `LLAMA_CPP_URL`, `OPENROUTER_URL`, `CURL_TIMEOUT_CLOUD` (longer HTTP timeout for cloud model lists, default 25s).

---

## Prerequisites

- [Claude Code](https://code.claude.com/) CLI on your PATH.
- `curl`, and either `jq` or Python 3 for JSON.
- **Per backend:** LM Studio (`lms`) or Ollama (`ollama`) or **llama.cpp** (`llama-server`) for local; API key for OpenRouter/Custom/NewAPI. Script prints install hints per platform (Linux/macOS/Windows).

---

## Installing the tools (for new visitors)

You need **Claude Code** (the CLI) and at least one **backend**. The script will prompt for missing tools and show install commands for your platform.

### 1. Install Claude Code

Go to **[code.claude.com/docs](https://code.claude.com/docs)** and follow the install instructions for your platform. Confirm with: `claude --version`. If you run Claudius without the CLI installed, it will offer **Install Claude Code now?** and run the official install script (Linux/macOS; works on Debian, Ubuntu, and most distros).

### 2. Install a backend (pick one or more)

- **LM Studio:** [lmstudio.ai](https://lmstudio.ai/) — install, download a model, start Local Inference Server (port 1234) or run `lms server start`.
- **Ollama:** [ollama.com](https://ollama.com) — install, then run `ollama serve` (and pull models with `ollama pull <name>`).
- **OpenRouter:** [openrouter.ai](https://openrouter.ai) — create an API key; Claudius will prompt for it at setup.
- **Custom (e.g. Alibaba DashScope):** Claudius preset uses the correct **Anthropic** base for Claude Code; you only need your Model Studio API key at setup.
- **llama.cpp:** Build/run [llama-server](https://github.com/ggerganov/llama.cpp) with an Anthropic-compatible / OpenAI stack as you prefer; default URL `http://127.0.0.1:8080`.

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

Start your backend first if local (LM Studio, Ollama, or llama-server), or when the server is not reachable choose **Remote** and enter the other machine’s address and backend type (LM Studio, Ollama, or llama.cpp). For OpenRouter/Custom ensure your API key is set. Then: choose model → for LM Studio only, choose context length and wait for load → script writes config and asks “Start Claude Code now? [Y/n]”. If you chose not to keep session history, after you exit Claude Code you get a menu to delete the current session, purge by age, or skip.

### Reset preferences (first-time questions again)

```bash
claudius --init
```

Re-asks: show reply duration, keep session history on exit, and **which backend** (1–6). Saves to `~/.claude/claudius-prefs.json`.  
If the script reported missing dependencies (required commands or backend app), install them, then run `claudius --init` to continue.

### Use last model and context (`--last`)

```bash
claudius --last
```

Uses the last base URL (backend), model, and context length from your previous run. Skips the model and context menus and starts Claude Code. If you have never run `claudius` to completion, the script reports "No last model saved" and exits. Combines with `--by-pass-start` to write config only: `claudius --last --by-pass-start`.

### Bypass start prompt (for scripts)

```bash
claudius --by-pass-start
claudius --init --by-pass-start
```

Runs the full flow (backend check, model selection, config write) but **does not** ask “Start Claude Code now?” and does not start the CLI. Exits after writing config. Use from your own scripts to configure Claude Code non-interactively or to chain with other tools.

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
# Alibaba (intl.): use Anthropic-compatible base (or omit URL and use prefs from --init)
CLAUDIUS_BACKEND=custom CLAUDIUS_BASE_URL=https://dashscope-intl.aliyuncs.com/apps/anthropic CLAUDIUS_API_KEY=sk-xxx claudius

# Override default URLs per backend (local or remote)
LMSTUDIO_URL=http://127.0.0.1:1234 claudius
OLLAMA_URL=http://192.168.1.10:11434 claudius
LLAMA_CPP_URL=http://192.168.1.10:8080 CLAUDIUS_BACKEND=llamacpp claudius

# Slower cloud model list (default 25s for OpenRouter/custom)
CURL_TIMEOUT_CLOUD=40 claudius
```

### Remote server (different machine)

When the local server is not running, choose **Remote** in the menu. Enter the server address (e.g. `192.168.1.10:1234`, `myserver:11434`, or `192.168.1.10:8080`) and whether it runs **LM Studio** (1234), **Ollama** (11434), or **llama.cpp** (8080). The script saves the URL to prefs and queries models on that host.

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
| Claudius prefs (backend, baseUrl, apiKey, lastModel, lastContextLength, turn duration, keep session) | `~/.claude/claudius-prefs.json` (first run or `claudius --init`; last model/context saved for `--last`) |
| Claude Code session data (purge with `claudius --purge`) | `~/.claude/projects`, `debug`, `file-history`, `history.jsonl`, etc. |
| Shell exports | **Auto-appended** to the right file for your shell (see [SHELL-SETUP.md](SHELL-SETUP.md)): `.bashrc`, `.zshrc`, `~/.config/fish/config.fish`, `.kshrc`/`.profile` |
| Default model | `defaultModel` in settings |

**Multi-shell:** Claudius detects your shell (`$SHELL` or `$CLAUDIUS_SHELL`) and appends ANTHROPIC_* vars with the correct syntax (e.g. `set -gx` for fish). **Env overrides:** `CLAUDIUS_BACKEND`, `CLAUDIUS_BASE_URL`, `CLAUDIUS_API_KEY`, `CLAUDIUS_AUTH_TOKEN` (llama.cpp), `LMSTUDIO_URL`, `OLLAMA_URL`, `LLAMA_CPP_URL`, `OPENROUTER_URL`, `CURL_TIMEOUT_CLOUD`. **Testing:** `claudius --dry-run` (or `--test`) runs server check and model selection without writing config or starting Claude.

## Changelog

- **0.9.5** (2026-03-22) – **Alibaba DashScope (intl.) + cloud list reliability.** Claude Code uses Anthropic’s Messages API; Alibaba’s correct base is `https://dashscope-intl.aliyuncs.com/apps/anthropic`, not `…/compatible-mode/v1` (that URL is for OpenAI-style listing and chat only). Claudius now stores the Anthropic base for the Alibaba preset, lists models via `compatible-mode/v1`, and **migrates existing prefs** that still had `compatible-mode/v1` as `baseUrl`. Custom `check`/`fetch` use a longer timeout (`CURL_TIMEOUT_CLOUD`, default 25s), connect timeout 5s, and **two curl retries**; the script retries the alternate `models` / `v1/models` path when the response has no `.data` models (fixes flaky empty lists). OpenRouter list uses the same timeout/retry. See [Alibaba Cloud: Anthropic API compatibility](https://www.alibabacloud.com/help/en/model-studio/anthropic-api-messages).
- **0.9.4** (2026-03-22) – **llama.cpp server backend** (`llamacpp`): OpenAI-compatible `GET /v1/models`, defaults `http://127.0.0.1:8080` and token `lmstudio`, optional remote on port 8080; writes `ENABLE_TOOL_SEARCH` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` for Claude Code. Init menu option **6**; prefs may include `authToken`.
- **0.9.3** (2026-03-15) – **`--last`:** Use last base URL, model, and context length; skip model menu and start Claude Code. The script saves `lastModel` and `lastContextLength` to `claudius-prefs.json` after each run. Run `claudius` once to set a "last" choice, then `claudius --last` to resume without menus. For LM Studio, if the same model is already loaded with the same context, load is skipped.
- **0.9.2** (2026-03-15) – **Claude Code CLI and shell setup:** Script ensures Claude Code CLI is installed (offers install when missing, including on first run). After writing config, it appends `~/.local/bin` to your shell’s PATH (so `claude` works in new terminals) and the **claudius** alias to your shell config if not already present. First-run and main flow both offer "Install Claude Code now?" when the CLI is missing.
- **0.9.1** (2026-03-15) – **`--by-pass-start`:** Do not ask to start Claude Code after setup; exit once config is written. Use with `claudius --by-pass-start` or `claudius --init --by-pass-start` to integrate the bootstrapper into other scripts.
- **0.9.0** (2026-03-15) – **NewAPI backend and more Custom presets.** **NewAPI:** New backend option 5 — [QuantumNous new-api](https://github.com/QuantumNous/new-api) unified gateway. Enter root URL (e.g. `http://localhost:8080`) and API key; script lists models via `GET /api/models` (channel→models), writes Claude Code base as `url/v1`. **Custom presets:** Added **xAI (Grok)** (`api.x.ai/v1`) and **OpenAI** (`api.openai.com/v1`); menu now 1–8 (Alibaba, Kimi, DeepSeek, Groq, OpenRouter, xAI, OpenAI, Other). Env/auth: NewAPI uses API key only (no auth conflict).
- **0.8.3** (2026-03-15) – **Custom provider presets:** When you choose backend **Custom**, a sub-menu offers: **Alibaba Cloud (DashScope)** (Singapore), **Kimi (Moonshot AI)** (global), **DeepSeek**, **Groq**, **OpenRouter** (alternative to backend 3), or **Other** (enter base URL and API key). Each preset uses the correct base URL for that provider; you only enter the API key. Endpoints were verified from official docs (list models: OpenAI-style `GET .../models` or `.../v1/models`, Bearer auth).
- **0.8.2** (2026-03-15) – **Custom/OpenRouter max tokens:** The “max N tokens” shown for each model is taken from the provider’s list-models response when available. The script now checks several common fields: `context_length`, `max_tokens`, `max_context_tokens`, `max_input_tokens`. If the API does not advertise any of these (e.g. some compatible-mode list endpoints), a fallback of 32768 is shown; that value is from Claudius, not the provider.
- **0.8.1** (2026-03-15) – **Remote server, already-loaded context, Claude Code install:** When LM Studio/Ollama server is not reachable, new option **3) Remote** prompts for server address (host or IP:port) and backend type (LM Studio/Ollama), saves to prefs and continues. **LM Studio:** if the selected model is already loaded, script shows current context length and offers keep or change (5+1 options); choosing keep skips unload/reload. **Claude Code CLI:** script prepends `~/.local/bin` to PATH before checking for `claude`, so an existing install there is detected even if the current shell has not loaded that path; if still missing, offers install. **Other:** ignore `backups/` in git; README title Claudius-Bootstrapper; clearer error when CLI not found.
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
- **Server not running** – For LM Studio/Ollama: start the server locally or choose **3) Remote** and enter the other machine’s IP:port and backend type (LM Studio 1234, Ollama 11434). Then choose 1 (Resume) to retry. For OpenRouter/Custom: check API key and network, then Retry.
- **Memory check / “Proceed anyway?”** – The script estimates RAM + VRAM need from model size and context length. If you see the notice, try a smaller context length (e.g. 2048 or 34304) to avoid LM Studio load failures. GPU detection: NVIDIA uses `nvidia-smi`; AMD and Intel (including Arc) use `/sys/class/drm` when the driver exposes VRAM info; if no GPU is detected, only system RAM is considered.
- **`lms` not found** – Add LM Studio’s CLI to PATH (e.g. `~/.lmstudio/bin`) or start the server from the GUI.
- **No models** – LM Studio: load at least one model and ensure the server is running. Ollama: run `ollama pull <name>` and ensure `ollama serve` is running. OpenRouter/Custom: check API key and base URL; the provider’s `GET .../models` must return a list.
- **Model load failed (HTTP 500)** – LM Studio could not load the model (e.g. out of memory, corrupt file, unsupported config). The script unloads any previously loaded model before loading; if it still fails, check **LM Studio server logs** for the exact error, try a smaller context length or another model. The script no longer continues to start Claude when load fails.
- **`claudius` not found** – Run `source ~/.bashrc` or open a new terminal.
- **`claude: not found` when starting** – Before checking, the script adds `~/.local/bin` to PATH (where the official installer puts `claude`), so an existing install is detected even if your current shell hasn’t loaded that path. If still missing, the script offers **Install Claude Code now? [y/N]**; say yes to run the official install script (Linux/macOS; Debian, Ubuntu, etc.). Then ensure `~/.local/bin` is in your shell config (`export PATH="$HOME/.local/bin:$PATH"`). Alternatively install from [code.claude.com/docs](https://code.claude.com/docs). Your config in `~/.claude/settings.json` is already set; you can also use the Claude Code extension in VS Code/Cursor with the same env vars.
- **Slow or no response** – Default `CURL_TIMEOUT` is 10s; cloud model lists use `CURL_TIMEOUT_CLOUD` (default **25s**) with retries. LM Studio load can take up to 300s. Use `claudius --dry-run` to test.
- **Alibaba / Qwen: model lists OK but Claude gets no reply** – You must use the **Anthropic-compatible** base `https://dashscope-intl.aliyuncs.com/apps/anthropic` in `ANTHROPIC_BASE_URL`, not `…/compatible-mode/v1`. Claudius **0.9.5+** sets this for the Alibaba preset and upgrades old prefs automatically; run `claudius --init` and re-pick Custom → Alibaba if needed.
- **Alibaba / custom: intermittent “cannot reach” or empty model list** – Try a higher `CURL_TIMEOUT_CLOUD` (e.g. `40`). Check API key and region (intl. Singapore vs mainland may differ).
- **Cursor (or VS Code) opens extra windows when starting Claude Code** – This comes from **Claude Code’s IDE integration**, not from Claudius. When the Claude Code extension is installed, starting the CLI (e.g. via `claudius`) can trigger the IDE to open panels or new windows. **Workaround:** run `claudius` from a terminal **outside** Cursor (e.g. a standalone terminal like GNOME Terminal, kitty, Alacritty). Alternatively, disable the Claude Code extension in Cursor when you only want terminal-only use. See [anthropics/claude-code#18205](https://github.com/anthropics/claude-code/issues/18205), [#8768](https://github.com/anthropics/claude-code/issues/8768).
- **Base URL** – LM Studio: `http://localhost:1234` with **no** `/v1` (Claude Code appends `/v1/messages`). **Alibaba intl.:** use `https://dashscope-intl.aliyuncs.com/apps/anthropic` for Claude Code; Claudius uses `compatible-mode/v1` only to **list** models.
- **OpenRouter / Custom: “Cannot reach” or empty model list** – Check API key (and for custom, base URL). Ensure no trailing slash on base URL unless the provider requires it.
- **Custom (e.g. Alibaba): all models show same “max 32768 tokens”** – The provider’s list-models response may not include per-model context size. Claudius shows 32768 as a fallback when the API omits `context_length`, `max_tokens`, `max_context_tokens`, or `max_input_tokens`. If your provider adds these fields to the list response, the script will display the real values.
- **“Auth conflict: Both a token and an API key are set”** – Claude Code errors when both `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_API_KEY` are set. Claudius now sets only one: for **custom** and **OpenRouter** it sets `ANTHROPIC_API_KEY` only; for LM Studio/Ollama it sets `ANTHROPIC_AUTH_TOKEN` only. If you still see this (e.g. from an older shell config), remove `ANTHROPIC_AUTH_TOKEN` from your shell config when using custom/OpenRouter so only `ANTHROPIC_API_KEY` remains.

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
