# Claudius

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Claudius is a bootstrapper to run [Claude Code](https://code.claude.com/) (Anthropic's agentic CLI) with local models served by [LM Studio](https://lmstudio.ai/), from the command line. No cloud, no proxy. The name refers to the fourth Roman emperor.

**Author:** Lefteris Iliadis ([Somnius](https://github.com/Somnius))  
**License:** [MIT](LICENSE)

---

## What it does

Claudius connects [Claude Code](https://code.claude.com/) (Anthropic’s CLI) to local models in [LM Studio](https://lmstudio.ai/) (no cloud, no proxy). Features:

| Feature | Description |
|--------|-------------|
| **First-time dependency check** | On first run (no prefs file), checks that LM Studio is installed (e.g. `lms` on PATH) and that required commands exist (curl, jq or python3, claude). If something is missing, prints where to get it and distro install hints, then asks you to install and run again with `claudius --init`. |
| **First-run preferences** | Asks whether to show reply duration (“Cooked for X”) and whether to keep session history on exit; saved in `~/.claude/claudius-prefs.json`. |
| **Server check** | Verifies LM Studio is reachable; offers Resume / Start (`lms server start`) / Abort if not. |
| **Model list** | Fetches models from LM Studio native API; shows each model’s max context length in a numbered menu. |
| **Context length** | Lets you pick a context size (5 suggested values or custom). Before loading, the script unloads any model already loaded in LM Studio (via `POST /api/v1/models/unload`), then loads the selected model with that length (spinner until done). |
| **Memory check** | Before loading, checks system RAM and GPU VRAM (NVIDIA, AMD, Intel). If estimated need exceeds available memory, shows a notice and asks “Proceed anyway? [y/N]” to avoid accidental load failures (e.g. HTTP 500). |
| **Config write** | Writes `~/.claude/settings.json` and appends shell exports once so Claude Code talks to LM Studio. |
| **Run Claude Code** | Starts `claude --model <chosen>`. |
| **Session on exit** | If you chose not to keep session history, after Claude Code exits you get a menu: delete current session only, purge all (2 confirmations), or purge by age (yesterday, 6h, 3h, 2h, 1h, 30 min), or skip. Only the option you choose runs; nothing is purged automatically. |
| **`--init`** | Re-ask first-run questions and overwrite saved preferences. |
| **`--purge`** | Interactive menu to purge saved session data: purge all (2 confirmations), purge last session only (~2 min), or purge by age (yesterday, 6h, 3h, 2h, 1h, 30 min). Settings and Claudius prefs are never removed. **No purge runs without explicit user choice for that option.** |
| **`--dry-run` / `--test`** | Run through server check, model and context selection without writing config or starting Claude. |

Claude Code talks to LM Studio’s Anthropic-compatible API. Claude Code is by [Anthropic](https://www.anthropic.com/); LM Studio by [LM Studio](https://lmstudio.ai/).

---

## Prerequisites

- [LM Studio](https://lmstudio.ai/) installed, at least one model available (script uses LM Studio’s native API to list and load models with a chosen context length).
- LM Studio local server (Local Inference Server in the app), or the `lms` CLI so the script can try to start it.
- [Claude Code](https://code.claude.com/) CLI on your PATH.
- `curl`, and either `jq` or Python 3 for JSON.

---

## Installing the tools (for new visitors)

You need **Claude Code** (the CLI) and **LM Studio** (to serve local models). Install them first, then use Claudius to connect the two.

### 1. Install Claude Code

Go to **[code.claude.com/docs](https://code.claude.com/docs)** (e.g. Quickstart) and follow the install instructions for your platform. Install methods may change; the official docs are the place to check. After installing, confirm with: `claude --version`.

### 2. Install LM Studio

- Download and install from **[lmstudio.ai](https://lmstudio.ai/)**.
- Open LM Studio, download at least one model, and start the **Local Inference Server** (default port 1234).  
  Or use the CLI: add `lms` to your PATH (e.g. `~/.lmstudio/bin`) and run `lms server start`.

### 3. Clone and use Claudius

```bash
git clone https://github.com/Somnius/Claudius-Bootstrapper.git ~/dev/Claudius-Bootstrapper
```

Add the alias for your shell (see [SHELL-SETUP.md](SHELL-SETUP.md)), then run `claudius` and pick your model.

---

## Usage

Set up the alias (see [SHELL-SETUP.md](SHELL-SETUP.md)) so `claudius` runs the script, or call the script by path.

### Run Claudius (normal flow)

```bash
claudius
```

Optionally start LM Studio and its Local Inference Server first; otherwise the script will prompt you. Then: choose model → choose context length → script loads the model → Claude Code starts. If you chose not to keep session history, after you exit Claude Code you get a menu to delete the current session, purge by age, or skip.

### Reset preferences (first-time questions again)

```bash
claudius --init
```

Re-asks: show reply duration? keep session history on exit? Saves to `~/.claude/claudius-prefs.json`.  
If the script reported missing dependencies (LM Studio or required commands), install them, then run `claudius --init` to continue.

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

### Override LM Studio URL

```bash
LMSTUDIO_URL=http://127.0.0.1:1234 claudius
```

## Alias

In `~/.bashrc` (adjust path if you cloned elsewhere):

```bash
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

Then `source ~/.bashrc` or open a new shell. For **zsh**, **fish**, **ksh**, and **sh**, see [SHELL-SETUP.md](SHELL-SETUP.md).

## Configuration

| What          | Where                     |
|---------------|----------------------------|
| Base URL, env | `~/.claude/settings.json`  |
| Claudius prefs (turn duration, keep session) | `~/.claude/claudius-prefs.json` (created on first run or `claudius --init`) |
| Claude Code session data (purge with `claudius --purge`) | `~/.claude/projects`, `debug`, `file-history`, `history.jsonl`, etc. |
| Shell exports | your shell config (see [SHELL-SETUP.md](SHELL-SETUP.md)) |
| Default model | `defaultModel` in settings |

**Settings template:** Copy [settings.json.example](settings.json.example) to `~/.claude/settings.json` and set `defaultModel` to your LM Studio model key. The script creates this file when you pick a model and context length. **First-run prefs:** On first run (or `claudius --init`) you are asked whether to show reply timing and whether to keep session history when exiting; both are saved in `~/.claude/claudius-prefs.json`.

Override LM Studio URL: `LMSTUDIO_URL=http://127.0.0.1:1234 claudius`.

**Testing:** Run `claudius --dry-run` (or `--test`) to go through server check, model selection, and context-length choice without writing config or starting Claude.

## Changelog

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
| [settings.json.example](settings.json.example) | Example `~/.claude/settings.json` — copy to `~/.claude/settings.json` and set `defaultModel` |
| `README.md`             | This file                                                  |
| `LICENSE`               | MIT license                                                |
| `.gitignore`            | Ignore notes, local/sensitive                              |

## Troubleshooting

- **First run: “Missing required command(s)” or “LM Studio does not appear to be installed”** – Install the missing tools (see the message for hints: curl, jq or python3, claude; LM Studio from https://lmstudio.ai). Then run `claudius --init` to continue.
- **Server not running** – Start Local Inference Server in LM Studio or run `lms server start`, then choose 1 (Resume).
- **Memory check / “Proceed anyway?”** – The script estimates RAM + VRAM need from model size and context length. If you see the notice, try a smaller context length (e.g. 2048 or 34304) to avoid LM Studio load failures. GPU detection: NVIDIA uses `nvidia-smi`; AMD and Intel (including Arc) use `/sys/class/drm` when the driver exposes VRAM info; if no GPU is detected, only system RAM is considered.
- **`lms` not found** – Add LM Studio’s CLI to PATH (e.g. `~/.lmstudio/bin`) or start the server from the GUI.
- **No models** – Load at least one model in LM Studio and ensure the server is running. The script uses the native list API (`/api/v1/models`).
- **Model load failed (HTTP 500)** – LM Studio could not load the model (e.g. out of memory, corrupt file, unsupported config). The script unloads any previously loaded model before loading; if it still fails, check **LM Studio server logs** for the exact error, try a smaller context length or another model. The script no longer continues to start Claude when load fails.
- **`claudius` not found** – Run `source ~/.bashrc` or open a new terminal.
- **Slow or no response** – Curl uses a 10s timeout (`CURL_TIMEOUT`); load can take up to 300s. Use `claudius --dry-run` to test.
- **Cursor (or VS Code) opens extra windows when starting Claude Code** – This comes from **Claude Code’s IDE integration**, not from Claudius. When the Claude Code extension is installed, starting the CLI (e.g. via `claudius`) can trigger the IDE to open panels or new windows. **Workaround:** run `claudius` from a terminal **outside** Cursor (e.g. a standalone terminal like GNOME Terminal, kitty, Alacritty). Alternatively, disable the Claude Code extension in Cursor when you only want terminal-only use. See [anthropics/claude-code#18205](https://github.com/anthropics/claude-code/issues/18205), [#8768](https://github.com/anthropics/claude-code/issues/8768).
- **Base URL** – Use `http://localhost:1234` with no trailing `/v1`; the script does this.

## Thanks & links

Claudius relies on these tools; thanks to their authors and communities.

| Tool | Purpose |
|------|---------|
| [Claude Code](https://code.claude.com/) (Anthropic) | Agentic CLI that talks to the model |
| [LM Studio](https://lmstudio.ai/) | Local inference server and model runtime — [API](https://lmstudio.ai/docs/api/endpoints/rest) (list, load with context length), [CLI](https://lmstudio.ai/docs/cli) |
| **curl** | HTTP requests to LM Studio (list, load) |
| **jq** or **Python 3** | JSON parsing of model list |
| **Bash** | Script runtime |

---
