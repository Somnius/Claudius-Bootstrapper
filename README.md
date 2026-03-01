# Claudius

Claudius is a bootstrapper to run [Claude Code](https://code.claude.com/) (Anthropic's agentic CLI) with local models served by [LM Studio](https://lmstudio.ai/), from the command line. No cloud, no proxy. The name refers to the fourth Roman emperor.

**Author:** Lefteris Iliadis ([Somnius](https://github.com/Somnius))  
**License:** [MIT](LICENSE)

---

## What it does

`claudius.sh`:

1. Checks that the LM Studio local server is running (default: `http://localhost:1234`).
2. If not, offers: Resume (you started it), Start (runs `lms server start`), or Abort.
3. Fetches the model list from LM Studio (`/v1/models`).
4. Lets you pick a model: with **fzf** or **gum** if installed, otherwise a numbered menu.
5. Writes `~/.claude/settings.json` (env and defaultModel) and appends exports to `~/.bashrc` once if needed.
6. Runs `claude --model <chosen>`.

Claude Code talks directly to LM Studio's Anthropic-compatible API. Claude Code is by [Anthropic](https://www.anthropic.com/). LM Studio is by [LM Studio](https://lmstudio.ai/).

## Prerequisites

- [LM Studio](https://lmstudio.ai/) installed, at least one model loaded.
- LM Studio local server (Local Inference Server in the app), or the `lms` CLI so the script can try to start it.
- [Claude Code](https://code.claude.com/) CLI on your PATH.
- `curl`, and either `jq` or Python 3 for JSON.
- Optional: [fzf](https://github.com/junegunn/fzf) or [gum](https://github.com/charmbracelet/gum) for a nicer model picker.

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
4. Pick a model (fzf/gum or number / q to quit).
5. Claude Code starts with that model.

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
| Shell exports | your shell config (see [SHELL-SETUP.md](SHELL-SETUP.md)) |
| Default model | `defaultModel` in settings |

**Settings template:** Copy [settings.json.example](settings.json.example) to `~/.claude/settings.json` and set `defaultModel` to your LM Studio model id (e.g. from `curl -s http://localhost:1234/v1/models`). The script can also create this file when you pick a model.

Override LM Studio URL: `LMSTUDIO_URL=http://127.0.0.1:1234 claudius`.

## Changelog

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
- **No models** – Load at least one model in LM Studio and ensure the server is running.
- **`claudius` not found** – Run `source ~/.bashrc` or open a new terminal.
- **Base URL** – Use `http://localhost:1234` with no trailing `/v1`; the script does this.

## Links

- [Claude Code](https://code.claude.com/) (Anthropic)
- [LM Studio](https://lmstudio.ai/) – [API](https://lmstudio.ai/docs/api/endpoints/rest), [CLI](https://lmstudio.ai/docs/cli)
