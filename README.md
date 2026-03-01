# Claudius

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Claudius is a bootstrapper to run [Claude Code](https://code.claude.com/) (Anthropic's agentic CLI) with local models served by [LM Studio](https://lmstudio.ai/), from the command line. No cloud, no proxy. The name refers to the fourth Roman emperor.

**Author:** Lefteris Iliadis ([Somnius](https://github.com/Somnius))  
**License:** [MIT](LICENSE)

---

## What it does

`claudius.sh`:

1. On first run (or `claudius --init`), asks whether to show reply duration and whether to **keep session history** when Claude Code exits; saves preferences to `~/.claude/claudius-prefs.json`.
2. Checks that the LM Studio local server is running (default: `http://localhost:1234`).
3. If not, offers: Resume (you started it), Start (runs `lms server start`), or Abort.
4. Fetches the model list from LM Studio (native API: `/api/v1/models`) and shows each model’s max context length.
5. Lets you pick a model from a numbered menu.
6. Asks you to choose a **context length** (tokens): suggests 5 values from min to the model’s max, or you can enter a custom number; then loads the model with that context length via LM Studio’s load API and **waits for the load to finish** (spinner; load can take 1–2 min). If load fails, the script exits.
7. Writes `~/.claude/settings.json` (env, defaultModel, showTurnDuration from prefs) and appends exports to your shell config once if needed.
8. Runs `claude --model <chosen>`. If you chose not to keep session history, the script clears session data from this run after Claude Code exits.

Claude Code talks directly to LM Studio's Anthropic-compatible API. Claude Code is by [Anthropic](https://www.anthropic.com/). LM Studio is by [LM Studio](https://lmstudio.ai/).

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

Official docs: **[code.claude.com/docs – Quickstart](https://code.claude.com/docs/en/quickstart)**.

**macOS / Linux / WSL (recommended):**

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**Homebrew (macOS):**

```bash
brew install --cask claude-code
```

**Windows:** See [Quickstart](https://code.claude.com/docs/en/quickstart) for PowerShell / WinGet options.

Check that it works: `claude --version`.

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

1. Optionally start LM Studio and its Local Inference Server on port 1234 and load a model. Otherwise the script will prompt you.
2. Run:

   ```bash
   claudius
   ```

   Add the alias to your shell config (see [SHELL-SETUP.md](SHELL-SETUP.md)); then run `source` your config or open a new terminal.

   Or run the script directly:

   ```bash
   ~/dev/Claudius-Bootstrapper/claudius.sh
   ```

3. If the server was not up, choose 1 (Resume), 2 (Start), or 3 (Abort).
4. Pick a model from the numbered list (or q to quit).
5. Choose a context length: pick one of 5 suggested values (min to model max) or enter a custom number; the script loads the model in LM Studio and waits for the load to finish (spinner; may take 1–2 min). If the load fails (e.g. HTTP 500), the script exits and does not start Claude — check LM Studio server logs.
6. Claude Code starts with the selected model.

**First-time setup:** On first run (or when `~/.claude/claudius-prefs.json` is missing), the script asks whether to show reply duration and whether to keep session history when Claude Code exits, then saves your choices. Run **`claudius --init`** anytime to be asked again and overwrite the saved preferences.

**Session purge:** Run **`claudius --purge`** to remove saved Claude Code session data under `~/.claude`. You can purge all (with two confirmation prompts), or purge by age: yesterday and back, 6h, 3h, 2h, 1h, or 30 minutes and back. Settings and Claudius prefs are not removed.

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

- **Server not running** – Start Local Inference Server in LM Studio or run `lms server start`, then choose 1 (Resume).
- **`lms` not found** – Add LM Studio’s CLI to PATH (e.g. `~/.lmstudio/bin`) or start the server from the GUI.
- **No models** – Load at least one model in LM Studio and ensure the server is running. The script uses the native list API (`/api/v1/models`).
- **Model load failed (HTTP 500)** – LM Studio could not load the model (e.g. out of memory, corrupt file, unsupported config). Check **LM Studio server logs** for the exact error; try a smaller context length or another model. The script no longer continues to start Claude when load fails.
- **`claudius` not found** – Run `source ~/.bashrc` or open a new terminal.
- **Slow or no response** – Curl uses a 10s timeout (`CURL_TIMEOUT`); load can take up to 300s. Use `claudius --dry-run` to test.
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
