# Claudius-Bootstrapper

[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Claudius is a multi-backend bootstrapper for [Claude Code](https://code.claude.com/) (Anthropic’s agentic CLI). It connects Claude Code to **LM Studio**, **Ollama**, **llama.cpp** (`llama-server`), **OpenRouter**, **Custom** (e.g. Alibaba DashScope, Kimi, DeepSeek), **NewAPI**, or **NVIDIA API** (NIM catalog on [integrate.api.nvidia.com](https://integrate.api.nvidia.com) — see limitations below). Supports Linux, macOS, and Windows (**native:** `claudius.bat` + `claudius.ps1`; **Git Bash/WSL:** `claudius.sh`). On Unix, writes env vars to your shell config (bash, zsh, fish, ksh, sh) automatically; on Windows, writes `%USERPROFILE%\.claude\settings.json` (same keys as `~/.claude/settings.json`).

**Author:** Lefteris Iliadis ([Somnius](https://github.com/Somnius))  
**License:** [MIT](LICENSE)

---

## Why Claude Code sometimes lists models but never “talks”

Claude Code always calls the **Anthropic Messages** API: it takes `ANTHROPIC_BASE_URL` and requests **`/v1/messages`** under that host. If the base URL already ends with `/v1` (or points at the wrong product surface), the real URL becomes wrong (e.g. **`…/v1/v1/messages`**) or hits an endpoint that does not implement Messages. The model **catalog** can still work, because many providers expose **`GET …/v1/models`** on a different path — so you get a long model list, then silence in chat.

| Backend | Typical mistake | What Claudius does (0.9.15+) |
|--------|------------------|------------------------------|
| **OpenRouter** | `ANTHROPIC_BASE_URL=https://openrouter.ai/api/v1` and/or auth via `ANTHROPIC_API_KEY` only | Uses **`https://openrouter.ai/api`** (no trailing `/v1`), **`ANTHROPIC_AUTH_TOKEN`** = your OpenRouter key, and **`ANTHROPIC_API_KEY=""`** exactly as in [OpenRouter’s Claude Code guide](https://openrouter.ai/docs/guides/coding-agents/claude-code-integration). Lists models from `https://openrouter.ai/api/v1/models`. Migrates old prefs that still had `…/api/v1`. |
| **Alibaba DashScope (intl.)** | `…/compatible-mode/v1` as Claude base, or API key only in `ANTHROPIC_API_KEY` | Uses **`…/apps/anthropic`** for chat and **`…/compatible-mode/v1`** only to list models ([Alibaba docs](https://www.alibabacloud.com/help/en/model-studio/anthropic-api-messages)). Writes the Model Studio key as **`ANTHROPIC_AUTH_TOKEN`** with **`ANTHROPIC_API_KEY=""`** (same pattern as OpenRouter). |
| **NVIDIA API (NIM)** | Expecting `integrate.api.nvidia.com` to implement Anthropic **`POST /v1/messages`** because **`GET /v1/models`** works | NVIDIA’s [LLM API docs](https://docs.api.nvidia.com/nim/reference/llm-apis) describe **`POST /v1/chat/completions`** (OpenAI-style). Claude Code only uses **`/v1/messages`**. Claudius can **list** models with your API key; **chat with Claude Code directly against this host usually fails** (model/access errors). Use an Anthropic↔OpenAI **proxy** (e.g. LiteLLM, claude-code-proxy) as `ANTHROPIC_BASE_URL`, or use **OpenRouter** / another Anthropic-native backend. Auth for settings: **`ANTHROPIC_AUTH_TOKEN`** + **`ANTHROPIC_API_KEY=""`** (same reason as OpenRouter — avoids `/login` fallback). |
| **Free / cheap OpenRouter models** | Same URL/auth issues as above | Fixing base + auth is required first. Some free models may be slow, rate-limited, or a poor match for agentic tool use; OpenRouter notes Claude Code is **guaranteed only with Anthropic first-party** routing — see their docs. |

### llama.cpp (`llama-server`) with Claude Code

Upstream **llama.cpp** implements the **Anthropic Messages API** on `llama-server` (POST `/v1/messages`, streaming, tools) — see the [Hugging Face announcement](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp) and [llama.cpp server docs](https://github.com/ggerganov/llama.cpp/blob/master/tools/server/README.md). **Recommended env for Claude Code:**

- **`ANTHROPIC_BASE_URL`** = server root only, e.g. `http://127.0.0.1:8080` (**no** extra `/v1`; the client adds `/v1/messages`).
- **`ANTHROPIC_AUTH_TOKEN`** = same string as **`llama-server`’s `--api-key`** when you use one; if the server has **no** API key, use an **empty** token in prefs (see script `authToken` / `get_llamacpp_auth_from_prefs`) or match whatever your gateway expects.
- **`ANTHROPIC_API_KEY=""`** in settings (explicit empty) avoids Claude Code falling back to real Anthropic credentials — same idea as OpenRouter’s docs.

Claudius defaults (`lmstudio`, compaction window, tool search) are a reasonable starting point; align the token with your **kickstart** or launch script (`local-llama` vs `lmstudio` vs none).

---

## What it does

Claudius lets you choose a backend, pick a model, and run Claude Code against it. It writes `~/.claude/settings.json` and appends the correct env vars to your **shell config** (detected from `$SHELL`: bash → `.bashrc`, zsh → `.zshrc`, fish → `~/.config/fish/config.fish`, ksh/sh → `.kshrc`/`.profile`).

| Feature | Description |
|--------|-------------|
| **Backends** | **LM Studio**, **Ollama**, **OpenRouter**, **Custom**, **NewAPI**, **llama.cpp server**, **NVIDIA API** (experimental listing / protocol caveat). Custom presets: Alibaba (DashScope), Kimi, DeepSeek, Groq, OpenRouter, xAI, OpenAI, or Other. NewAPI: [QuantumNous new-api](https://github.com/QuantumNous/new-api). **llama.cpp:** `llama-server` (local or remote). Choose once at setup or with `claudius --init`. |
| **First-time / `--init`** | Asks: show reply duration, keep session on exit, and **which backend** (1–7). Saves to `~/.claude/claudius-prefs.json`. For OpenRouter/Custom/NewAPI/NVIDIA/llama.cpp, prompts for API key or token and URL where needed. **NVIDIA:** shows protocol warnings (OpenAI vs Anthropic). |
| **Platform & deps** | Detects Linux/macOS/Windows and prints install hints for curl, jq, claude (e.g. apt/dnf/pacman on Linux, brew on macOS). Does not auto-install packages. |
| **Server check** | LM Studio/Ollama: Resume / Start local / **Remote** / Abort. **llama.cpp:** Resume / Remote / Abort. **Remote:** LM Studio/Ollama flows ask for address then server type (LM Studio 1234, Ollama 11434, or llama.cpp 8080). **llama.cpp** flow only: Remote skips that menu; address prompt shows saved host (**Enter** = keep for retry). OpenRouter/Custom/NewAPI/NVIDIA: Retry / Abort. |
| **Model list** | LM Studio native API, Ollama `/api/tags`, OpenRouter `GET …/api/v1/models`, Custom Bearer `GET …/models`, NewAPI `GET /api/models`, llama.cpp `GET …/v1/models`, **NVIDIA** `GET {host}/v1/models` + Bearer. **Alibaba (intl.):** list via `compatible-mode/v1`; chat base `apps/anthropic` (see [Why no replies](#why-claude-code-sometimes-lists-models-but-never-talks)). |
| **Context length** | **LM Studio only:** loaded-model keep/change, then load with chosen context. Other backends: no load step. |
| **Memory check** | **LM Studio only:** checks RAM/VRAM before load and warns if insufficient. |
| **Config & shell** | Writes `~/.claude/settings.json` and shell exports. **OpenRouter** and **NVIDIA API:** `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_API_KEY=""` (OpenRouter docs pattern; avoids Claude Code `/login` when using third-party hosts). **Alibaba DashScope** (`custom`, `…/apps/anthropic`): same as OpenRouter. **Other custom / NewAPI:** `ANTHROPIC_API_KEY` only. **LM Studio / Ollama:** `ANTHROPIC_AUTH_TOKEN` only. **llama.cpp:** token + empty `ANTHROPIC_API_KEY` + optional compaction/tool-search env. Ensures Claude CLI and PATH/alias as before. |
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
| **OpenRouter** | `https://openrouter.ai/api` | OpenRouter key as **`ANTHROPIC_AUTH_TOKEN`**, **`ANTHROPIC_API_KEY=""`** | Claude Code base must **not** include `/v1`. Model list: `GET https://openrouter.ai/api/v1/models`. See [OpenRouter Claude Code integration](https://openrouter.ai/docs/guides/coding-agents/claude-code-integration). |
| **Custom** | Preset or user URL | API key (Bearer) | Presets: **Alibaba (DashScope, Singapore/intl.)**, **Kimi**, **DeepSeek**, **Groq**, **OpenRouter**, **xAI**, **OpenAI**, or **Other**. **Alibaba:** [Anthropic-compatible base](https://www.alibabacloud.com/help/en/model-studio/anthropic-api-messages) `https://dashscope-intl.aliyuncs.com/apps/anthropic`; Claudius writes your key as **`ANTHROPIC_AUTH_TOKEN`** with **`ANTHROPIC_API_KEY=""`** (same idea as OpenRouter). Model list still uses `…/compatible-mode/v1`. |
| **NewAPI** | User (e.g. `http://localhost:8080`) | API key (Bearer) | [QuantumNous new-api](https://github.com/QuantumNous/new-api) unified gateway. Root URL in prefs; Claude Code uses `base/v1`. Model list from `GET /api/models`. |
| **NVIDIA API** | `https://integrate.api.nvidia.com` (default; override `NVIDIA_URL` / prefs) | Key as **`ANTHROPIC_AUTH_TOKEN`**, **`ANTHROPIC_API_KEY=""`** | Lists via **`GET …/v1/models`** + Bearer ([build.nvidia.com](https://build.nvidia.com) keys). **Claude Code chat:** host documents **OpenAI** `chat/completions`, not Anthropic `messages` — see table above and [NIM LLM APIs](https://docs.api.nvidia.com/nim/reference/llm-apis). Base URL stored **without** trailing `/v1` (normalized if you paste `…/v1`). |
| **llama.cpp** | `http://127.0.0.1:8080` (default) | `ANTHROPIC_AUTH_TOKEN` = server `--api-key` if any; `ANTHROPIC_API_KEY=""` | Use **Anthropic Messages**-capable `llama-server` ([overview](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp)). Base URL = **origin only** (no `/v1`); you may enter `host:8080` or `http://host:8080` — Claudius normalizes to **`http://…`**. Lists models via **`GET …/v1/models`**; match token to your launch script. |

Override with env: `CLAUDIUS_BACKEND`, `CLAUDIUS_BASE_URL`, `CLAUDIUS_API_KEY`, `CLAUDIUS_AUTH_TOKEN` (llama.cpp), `LMSTUDIO_URL`, `OLLAMA_URL`, `LLAMA_CPP_URL`, `OPENROUTER_URL`, `NVIDIA_URL`, `CURL_TIMEOUT_CLOUD` (longer HTTP timeout for cloud model lists, default 25s).

---

## Prerequisites

- [Claude Code](https://code.claude.com/) CLI on your PATH.
- `curl`, and either `jq` or Python 3 for JSON.
- **Per backend:** LM Studio (`lms`) or Ollama (`ollama`) or **llama.cpp** (`llama-server`) for local; API key for OpenRouter/Custom/NewAPI/NVIDIA. Script prints install hints per platform (Linux/macOS/Windows).

---

## Installing the tools (for new visitors)

You need **Claude Code** (the CLI) and at least one **backend**. The script will prompt for missing tools and show install commands for your platform.

### 1. Install Claude Code

Go to **[code.claude.com/docs](https://code.claude.com/docs)** and follow the install instructions for your platform. Confirm with: `claude --version`. If you run Claudius without the CLI installed, it will offer **Install Claude Code now?** and run the official install script (Linux/macOS; works on Debian, Ubuntu, and most distros).

### 2. Install a backend (pick one or more)

- **LM Studio:** [lmstudio.ai](https://lmstudio.ai/) — install, download a model, start Local Inference Server (port 1234) or run `lms server start`.
- **Ollama:** [ollama.com](https://ollama.com) — install, then run `ollama serve` (and pull models with `ollama pull <name>`).
- **OpenRouter:** [openrouter.ai](https://openrouter.ai) — create an API key; Claudius will prompt for it at setup.
- **NVIDIA API:** [build.nvidia.com](https://build.nvidia.com) — API key for cloud inference; read the **OpenAI vs Anthropic** limitation in [Why lists but no chat](#why-claude-code-sometimes-lists-models-but-never-talks) before relying on it for Claude Code.
- **Custom (e.g. Alibaba DashScope):** Claudius preset uses the correct **Anthropic** base for Claude Code; you only need your Model Studio API key at setup.
- **llama.cpp:** Build [llama-server](https://github.com/ggerganov/llama.cpp) with **Anthropic Messages** support; point Claudius at `http://127.0.0.1:8080` (or your bind address). Use the same API key string in Claudius as in `llama-server --api-key` when applicable.

### 3. Clone and use Claudius

```bash
git clone https://github.com/Somnius/Claudius-Bootstrapper.git ~/dev/Claudius-Bootstrapper
```

Add the alias for your shell (see [SHELL-SETUP.md](SHELL-SETUP.md)), then run `claudius`. On first run you choose backend and preferences; then pick a model and (for LM Studio) context length. Claudius appends env vars to the **correct config file** for your shell (bash/zsh/fish/ksh/sh).

**Windows (cmd or PowerShell):** From the repo directory, run `claudius.bat`, or invoke the script directly:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\claudius.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\claudius.ps1 --init --dry-run
```

The same options as `claudius.sh` (`--init`, `--dry-run`, `--last`, `--purge`, …) work for both `claudius.bat` and `claudius.ps1`. Global config is `%USERPROFILE%\.claude\settings.json`.

---

## Usage

Set up the alias (see [SHELL-SETUP.md](SHELL-SETUP.md)) so `claudius` runs the script, or call the script by path.

### Run Claudius (normal flow)

```bash
claudius
```

Start your backend first if local (LM Studio, Ollama, or llama-server), or when the server is not reachable choose **Remote** and enter the other machine’s address and backend type (LM Studio, Ollama, or llama.cpp). For cloud backends (OpenRouter, Custom, NewAPI, NVIDIA) ensure your API key is set in prefs or env. Then: choose model → for LM Studio only, choose context length and wait for load → script writes config and asks “Start Claude Code now? [Y/n]”. If you chose not to keep session history, after you exit Claude Code you get a menu to delete the current session, purge by age, or skip.

### Reset preferences (first-time questions again)

```bash
claudius --init
```

Re-asks: show reply duration, keep session history on exit, and **which backend** (1–7). Saves to `~/.claude/claudius-prefs.json`.  
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
# OpenRouter: base must be .../api (script sets AUTH_TOKEN + empty API_KEY in settings)
CLAUDIUS_BACKEND=openrouter CLAUDIUS_BASE_URL=https://openrouter.ai/api CLAUDIUS_API_KEY=sk-or-v1-xxx claudius
# Alibaba (intl.): Anthropic-compatible base (or omit URL and use prefs from --init)
CLAUDIUS_BACKEND=custom CLAUDIUS_BASE_URL=https://dashscope-intl.aliyuncs.com/apps/anthropic CLAUDIUS_API_KEY=sk-xxx claudius
# NVIDIA (listing / prefs; chat needs proxy unless your gateway implements Anthropic /v1/messages)
CLAUDIUS_BACKEND=nvidia CLAUDIUS_API_KEY=nvapi-xxxxx claudius
# Optional: default host https://integrate.api.nvidia.com
NVIDIA_URL=https://integrate.api.nvidia.com claudius

# Override default URLs per backend (local or remote)
LMSTUDIO_URL=http://127.0.0.1:1234 claudius
OLLAMA_URL=http://192.168.1.10:11434 claudius
LLAMA_CPP_URL=http://192.168.1.10:8080 CLAUDIUS_BACKEND=llamacpp claudius

# Slower cloud model list (default 25s for OpenRouter/custom)
CURL_TIMEOUT_CLOUD=40 claudius
```

### Remote server (different machine)

When the local server is not running, choose **Remote** in the menu. Enter the server address (e.g. `192.168.1.10:1234`, `myserver:11434`, or `192.168.1.10:8080`) and, for **LM Studio** or **Ollama**, whether the host runs LM Studio (1234), Ollama (11434), or llama.cpp (8080). **If your backend is already llama.cpp**, Remote does **not** ask again for backend type; the prompt shows your saved host and **Enter** keeps it (e.g. to retry after starting the server). Prefs and `--init` store llama bases with a proper **`http://`** scheme so health checks work.

### Using Claude Code in VS Code (chat panel)

Claudius runs the **CLI** in the terminal. To use the **Claude Code extension** in VS Code (chat panel, Spark icon) with the **same** backend: install the [Claude Code extension](https://marketplace.visualstudio.com/items?itemName=Anthropic.claude-code), then in VS Code **user settings** (JSON) set the same env vars Claudius wrote to your shell (from `~/.claude/settings.json`):

```json
"claudeCode.environmentVariables": [
  { "name": "ANTHROPIC_BASE_URL", "value": "http://localhost:1234" },
  { "name": "ANTHROPIC_AUTH_TOKEN", "value": "lmstudio" }
]
```

For **LM Studio** use `lmstudio` as `ANTHROPIC_AUTH_TOKEN`. For **OpenRouter**, **NVIDIA API**, and **Alibaba DashScope** (`…/apps/anthropic`) mirror `settings.json`: `ANTHROPIC_AUTH_TOKEN` = your key, `ANTHROPIC_API_KEY` = `""`. For **other Custom** and **NewAPI** use `ANTHROPIC_API_KEY` only. Set the extension’s default model to your chosen model ID.

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

**Multi-shell:** Claudius detects your shell (`$SHELL` or `$CLAUDIUS_SHELL`) and appends ANTHROPIC_* vars with the correct syntax (e.g. `set -gx` for fish). **Env overrides:** `CLAUDIUS_BACKEND`, `CLAUDIUS_BASE_URL`, `CLAUDIUS_API_KEY`, `CLAUDIUS_AUTH_TOKEN` (llama.cpp), `LMSTUDIO_URL`, `OLLAMA_URL`, `LLAMA_CPP_URL`, `OPENROUTER_URL`, `NVIDIA_URL`, `CURL_TIMEOUT_CLOUD`. **Testing:** `claudius --dry-run` (or `--test`) runs server check and model selection without writing config or starting Claude. If your shell block was appended under an older backend, remove the old “Claude Code → Claudius” section so a fresh run can append the right vars (or edit by hand).

## Changelog

- **0.9.15** (2026-04-04) – **NVIDIA API backend (optional):** Init/menu option **7** / `CLAUDIUS_BACKEND=nvidia`. Lists models via **`GET {host}/v1/models`** with Bearer key; default host **`https://integrate.api.nvidia.com`** (`NVIDIA_URL`). Writes **`ANTHROPIC_AUTH_TOKEN`** + **`ANTHROPIC_API_KEY=""`** (same pattern as OpenRouter) so Claude Code does not fall back to **`/login`**. **Caveat:** NVIDIA’s public NIM HTTP API documents **OpenAI** `POST /v1/chat/completions`; Claude Code uses **Anthropic** `POST /v1/messages` — listing works, **direct chat against integrate.api usually does not**; scripts print warnings; use a proxy or an Anthropic-native backend for real sessions. README: this section + troubleshooting. Parity in **`claudius.ps1`**.
- **0.9.14** (2026-03-29) – **Windows `claudius.ps1` reliability:** **`claudius.ps1` ships with a UTF-8 BOM** so **`powershell.exe -File`** (5.1) decodes the file as UTF-8; without a BOM, UTF-8 multibyte characters (e.g. former Unicode arrows/em dashes) could be read using the system ANSI code page and **break parsing** (false “missing `}`” / bad `Write-Host` errors). User-facing strings in **`claudius.ps1`** are **ASCII-only** for the same reason. **`Invoke-CurlString`** builds **`curl.exe` args with `System.Collections.Generic.List[string]`** so splatting on PS 5.1 does not **drop the URL** (`curl: (2) no URL specified`). Also: **`New-ClaudiusModelEntryString`** for `key|max` lines, expanded **`Resolve-Backend`** `switch` blocks, single expandable string for the model menu line, spacing fix for **`'openrouter'`** in **`Get-ModelsForBackend`**.
- **0.9.13** (2026-03-28) – **Windows `claudius.ps1`:** **Pipe split fix:** `$ln.Split([char]'|', 2)` is invalid — PowerShell treats the **`|`** after **`]`** as a **pipeline** token, not as part of a character literal, which caused “Expressions are only allowed as the first element of a pipeline” and a cascade of parse errors. Use **`[char]0x7C`** (ASCII 124) instead. **`$str.Split('|')`** with the pipe **inside** quotes is fine.
- **0.9.12** (2026-03-28) – **Windows `claudius.ps1`:** Removed the **RAM/GPU memory pre-check** before LM Studio load (`Get-CimInstance`, `nvidia-smi`, estimates, confirm prompt). That block caused **PowerShell parse/runtime issues** on Windows; **Unix `claudius.sh` still has the full check.** On Windows, if the model does not fit memory, LM Studio load fails — use the app’s logs. Notes are in **`claudius.ps1`** above `Write-SettingsJson`.
- **0.9.11** (2026-03-28) – **Windows `claudius.ps1`:** Follow-up to **0.9.10**: an explanatory **comment** still contained single-quoted `'\|'` fragments. PowerShell tokenizes those as string literals even on a `#` line, so **PS 5.1 and PS 7** hit the same “`\` ends string, `|` becomes pipeline” error. **0.9.10** should **`git pull`** to **0.9.11** (comment reworded; runtime split logic unchanged).
- **0.9.10** (2026-03-28) – **Windows `claudius.ps1` parser fix:** Replaced `-split '\|'` with **`String.Split('|')`** for model `key|maxContext` lines. In **Windows PowerShell 5.1**, single-quoted `'\'` ends the string after the backslash, so the following `|` was parsed as a **pipeline** and broke the whole script (cascade of “missing `}`”, “Unexpected token”). **0.9.9** `claudius.ps1` on PS 5.1 should upgrade to **0.9.10**.
- **0.9.9** (2026-03-28) – **Windows native bootstrapper:** Added **`claudius.bat`** (cmd launcher) and **`claudius.ps1`** (PowerShell implementation, parity with `claudius.sh`). Config under **`%USERPROFILE%\.claude\`**. Run `claudius.bat` or `powershell -NoProfile -File path\to\claudius.ps1` with the same flags as the shell script (`--init`, `--dry-run`, `--last`, etc.). Renamed from earlier `claudius-windows.ps1`.
- **0.9.8** (2026-03-22) – **llama.cpp remote UX + URL normalization:** If the server is down and you pick **Remote** while backend is **llamacpp**, the script no longer asks a second time which backend runs on the host (it stays llama.cpp / port 8080). The address prompt shows the current value; **Enter** keeps it for an easy retry. **`--init`** and loading prefs normalize llama base URLs like `192.168.x.x:8080` to **`http://192.168.x.x:8080`** so `curl` health checks and model list requests work.
- **0.9.7** (2026-03-22) – **Alibaba DashScope auth alignment:** For **Custom** with base URL matching **DashScope** and **`/apps/anthropic`**, `~/.claude/settings.json`, shell exports, and session env now use **`ANTHROPIC_AUTH_TOKEN`** (your Model Studio API key) and **`ANTHROPIC_API_KEY=""`**, matching the OpenRouter-style third-party Anthropic pattern and restoring the intent of the older v0.9.4 GitHub branch. **Other** custom providers and **NewAPI** still use **`ANTHROPIC_API_KEY`** only. README and **CLAUDE.md** updated (env vars, auth troubleshooting, VS Code extension note).
- **0.9.6** (2026-03-22) – **OpenRouter + Claude Code:** default base is now **`https://openrouter.ai/api`** (not `…/api/v1`). Settings and shell exports use **`ANTHROPIC_AUTH_TOKEN`** (OpenRouter key) and explicit **`ANTHROPIC_API_KEY=""`**, matching [OpenRouter’s Claude Code guide](https://openrouter.ai/docs/guides/coding-agents/claude-code-integration). Model listing uses **`GET …/api/v1/models`**. Prefs that still had `openrouter.ai/api/v1` are migrated to `…/api`. **Docs:** new section *Why Claude Code sometimes lists models but never “talks”* (wrong `/v1` / wrong auth); **llama.cpp** guidance aligned with upstream Anthropic Messages support ([HF note](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp)).
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
| `claudius.sh`           | Bootstrapper script (Linux, macOS, Git Bash, WSL)         |
| `claudius.bat`          | Windows cmd launcher; runs `claudius.ps1`                |
| `claudius.ps1`          | Windows PowerShell bootstrapper (same options as `claudius.sh`) |
| [SHELL-SETUP.md](SHELL-SETUP.md) | How to add the `claudius` alias on **bash**, **zsh**, **fish**, **ksh**, and **sh** |
| [settings.json.example](settings.json.example) | Example `~/.claude/settings.json` (LM Studio). Base URL and auth depend on backend; Claudius writes this when you pick a model. |
| `README.md`             | This file                                                  |
| `LICENSE`               | MIT license                                                |
| `.gitignore`            | Ignore notes, local/sensitive; also `CLAUDE.md`, `GUIDE-VSCODE-CLAUDE-CHAT.md`, `discussion-log.md` |

Optional local docs (gitignored, not in the repo by default): `GUIDE-VSCODE-CLAUDE-CHAT.md` (step-by-step: Claude Code in VS Code chat panel + LM Studio + MCP), `CLAUDE.md` (project-specific Claude instructions), `discussion-log.md` (session notes and decisions).

## Troubleshooting

- **Windows: `claudius.ps1` parse errors** (“Expressions are only allowed as the first element of a pipeline”, “Missing closing `}`”, `Write-Host` / `)` errors) – **`git pull`** to **v0.9.14+** — UTF-8 **BOM** + **ASCII-only** strings in **`claudius.ps1`** for **PS 5.1 `-File`** encoding; plus **`[char]0x7C`** / **`New-ClaudiusModelEntryString`** and earlier **0.9.10–0.9.13** fixes. See changelog **0.9.14**.
- **Windows: `curl: (2) no URL specified` from `claudius.ps1`** – Fixed in **v0.9.14**: **`Invoke-CurlString`** uses a **`List[string]`** argument list for **`curl.exe`** so Windows **PowerShell 5.1** does not omit the URL when invoking native commands. **`git pull`** and run **`claudius.bat`** again.
- **Windows: no RAM/GPU pre-check** – **v0.9.12+** `claudius.ps1` no longer runs the memory estimate before LM Studio load (that logic remains in **`claudius.sh`** only). If load fails, reduce context or model size and check LM Studio logs.
- **First run: “Missing required command(s)” or backend not installed** – Install the missing tools (script prints platform-specific hints: curl, jq, claude). For LM Studio install from https://lmstudio.ai; for Ollama from https://ollama.com. Then run `claudius --init` to continue.
- **Server not running** – For LM Studio/Ollama: start the server locally or choose **Remote**, enter IP:port, and pick backend type (LM Studio 1234, Ollama 11434, or llama.cpp 8080). For **llama.cpp** with Remote: no second backend menu; **Enter** at the address prompt keeps the saved host. Then choose **Resume** to retry. For OpenRouter/Custom/NewAPI/NVIDIA: check API key and network, then Retry.
- **llama.cpp “not reachable” but server is up** – Ensure the saved base URL includes **`http://`** (Claudius **0.9.8+** adds it automatically for `host:port`). Check firewall, bind address (`0.0.0.0` vs localhost), and that **`GET /v1/models`** responds (and Bearer token if you use `--api-key`).
- **Memory check / “Proceed anyway?”** – The script estimates RAM + VRAM need from model size and context length. If you see the notice, try a smaller context length (e.g. 2048 or 34304) to avoid LM Studio load failures. GPU detection: NVIDIA uses `nvidia-smi`; AMD and Intel (including Arc) use `/sys/class/drm` when the driver exposes VRAM info; if no GPU is detected, only system RAM is considered.
- **`lms` not found** – Add LM Studio’s CLI to PATH (e.g. `~/.lmstudio/bin`) or start the server from the GUI.
- **No models** – LM Studio: load at least one model and ensure the server is running. Ollama: run `ollama pull <name>` and ensure `ollama serve` is running. OpenRouter/Custom/NewAPI/NVIDIA: check API key and base URL; the provider’s list endpoint must return models.
- **Model load failed (HTTP 500)** – LM Studio could not load the model (e.g. out of memory, corrupt file, unsupported config). The script unloads any previously loaded model before loading; if it still fails, check **LM Studio server logs** for the exact error, try a smaller context length or another model. The script no longer continues to start Claude when load fails.
- **`claudius` not found** – Run `source ~/.bashrc` or open a new terminal.
- **`claude: not found` when starting** – Before checking, the script adds `~/.local/bin` to PATH (where the official installer puts `claude`), so an existing install is detected even if your current shell hasn’t loaded that path. If still missing, the script offers **Install Claude Code now? [y/N]**; say yes to run the official install script (Linux/macOS; Debian, Ubuntu, etc.). Then ensure `~/.local/bin` is in your shell config (`export PATH="$HOME/.local/bin:$PATH"`). Alternatively install from [code.claude.com/docs](https://code.claude.com/docs). Your config in `~/.claude/settings.json` is already set; you can also use the Claude Code extension in VS Code/Cursor with the same env vars.
- **Slow or no response** – Default `CURL_TIMEOUT` is 10s; cloud model lists use `CURL_TIMEOUT_CLOUD` (default **25s**) with retries. LM Studio load can take up to 300s. Use `claudius --dry-run` to test.
- **Alibaba / Qwen: model lists OK but Claude gets no reply** – Use **`https://dashscope-intl.aliyuncs.com/apps/anthropic`**, not `…/compatible-mode/v1`. Claudius **0.9.5+** sets this for the Alibaba preset and upgrades old prefs; run `claudius --init` if needed. **0.9.7+** also writes DashScope chat auth as **`ANTHROPIC_AUTH_TOKEN`** + empty **`ANTHROPIC_API_KEY`** (see [Why no replies](#why-claude-code-sometimes-lists-models-but-never-talks)).
- **OpenRouter: long model list but no replies (including `:free` models)** – Base URL must be **`https://openrouter.ai/api`** (no `/v1`). Auth must be **`ANTHROPIC_AUTH_TOKEN`** with **`ANTHROPIC_API_KEY=""`**, not API-key–only. Claudius **0.9.6+** does this and migrates old `…/api/v1` prefs. After fixing, `/status` in Claude Code should show the OpenRouter base. If a free model still misbehaves, try another model or check OpenRouter activity for errors.
- **NVIDIA: model list OK, chat says model missing / no access, or only “API Usage Billing”** – The catalog uses **`GET /v1/models`**; Claude Code sends **`POST /v1/messages`**. NVIDIA’s docs center on **`POST /v1/chat/completions`**. **Claudius cannot bridge that in the shell** — use an Anthropic-compatible proxy pointed at NVIDIA’s OpenAI API, or switch backend (e.g. OpenRouter if the model is offered there). Auth for NVIDIA in settings is **`ANTHROPIC_AUTH_TOKEN`** + empty **`ANTHROPIC_API_KEY`** (**0.9.15+**); if you still see **`/login`**, refresh `settings.json` and shell exports (remove duplicate old env block if Claudius skipped re-append).
- **Alibaba / custom: intermittent “cannot reach” or empty model list** – Try a higher `CURL_TIMEOUT_CLOUD` (e.g. `40`). Check API key and region (intl. Singapore vs mainland may differ).
- **Cursor (or VS Code) opens extra windows when starting Claude Code** – This comes from **Claude Code’s IDE integration**, not from Claudius. When the Claude Code extension is installed, starting the CLI (e.g. via `claudius`) can trigger the IDE to open panels or new windows. **Workaround:** run `claudius` from a terminal **outside** Cursor (e.g. a standalone terminal like GNOME Terminal, kitty, Alacritty). Alternatively, disable the Claude Code extension in Cursor when you only want terminal-only use. See [anthropics/claude-code#18205](https://github.com/anthropics/claude-code/issues/18205), [#8768](https://github.com/anthropics/claude-code/issues/8768).
- **Base URL** – LM Studio / llama.cpp: origin only, **no** `/v1`. **OpenRouter:** `https://openrouter.ai/api` only. **Alibaba intl.:** `https://dashscope-intl.aliyuncs.com/apps/anthropic` for chat; Claudius lists via `compatible-mode/v1`.
- **OpenRouter / Custom: “Cannot reach” or empty model list** – Check API key (and for custom, base URL). Ensure no trailing slash on base URL unless the provider requires it.
- **Custom (e.g. Alibaba): all models show same “max 32768 tokens”** – The provider’s list-models response may not include per-model context size. Claudius shows 32768 as a fallback when the API omits `context_length`, `max_tokens`, `max_context_tokens`, or `max_input_tokens`. If your provider adds these fields to the list response, the script will display the real values.
- **“Auth conflict” or wrong provider** – Do not mix real Anthropic credentials with a third-party base URL. **OpenRouter** and **NVIDIA API** require **`ANTHROPIC_AUTH_TOKEN`** + **`ANTHROPIC_API_KEY=""`**. **Alibaba DashScope** (`…/apps/anthropic`, custom preset): same. **Other custom / NewAPI:** **`ANTHROPIC_API_KEY`** only (unset token). **LM Studio/Ollama:** **`ANTHROPIC_AUTH_TOKEN`** only (unset API key). **llama.cpp:** token + empty API key in settings. Remove stale exports from old shell blocks if you switched backends.

## Thanks & links

Claudius relies on these tools; thanks to their authors and communities.

| Tool | Purpose |
|------|---------|
| [Claude Code](https://code.claude.com/) (Anthropic) | Agentic CLI that talks to the model |
| [LM Studio](https://lmstudio.ai/) | Local inference — [API](https://lmstudio.ai/docs/api/endpoints/rest), [CLI](https://lmstudio.ai/docs/cli) |
| [Ollama](https://ollama.com) | Local inference — `/api/tags` for model list |
| [OpenRouter](https://openrouter.ai) | Cloud — [Claude Code integration](https://openrouter.ai/docs/guides/coding-agents/claude-code-integration) |
| [NVIDIA NIM / API Catalog](https://docs.api.nvidia.com/nim/reference/llm-apis) | Cloud model listing / OpenAI-style chat (`integrate.api.nvidia.com`) |
| [llama.cpp server](https://github.com/ggerganov/llama.cpp) | [Anthropic Messages in llama-server](https://huggingface.co/blog/ggml-org/anthropic-messages-api-in-llamacpp) |
| **curl** | HTTP requests (list models, load for LM Studio) |
| **jq** or **Python 3** | JSON parsing of model list |
| **Bash** | Script runtime |

---
