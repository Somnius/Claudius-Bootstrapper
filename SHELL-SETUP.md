# Shell setup — making `claudius` available

Add the following to your shell’s config file so you can run `claudius` from any terminal.  
**Adjust the script path** if you did not clone this repo to `~/dev/Claudius-Bootstrapper`.

---

## Bash

**Config file:** `~/.bashrc` (or `~/.bash_aliases` if you source it from `.bashrc`)

```bash
# Claudius — Claude Code + LM Studio bootstrapper (run: claudius)
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

Then run `source ~/.bashrc` (or open a new terminal).

---

## Zsh

**Config file:** `~/.zshrc`

```bash
# Claudius — Claude Code + LM Studio bootstrapper (run: claudius)
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

Then run `source ~/.zshrc` (or open a new terminal).

---

## Fish

**Config file:** `~/.config/fish/config.fish` (create the directory with `mkdir -p ~/.config/fish` if needed)

Fish uses `alias` as a wrapper for `function`; the syntax is different:

```fish
# Claudius — Claude Code + LM Studio bootstrapper (run: claudius)
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

Or define a function explicitly (works in all Fish versions):

```fish
# Claudius — Claude Code + LM Studio bootstrapper (run: claudius)
function claudius
    ~/dev/Claudius-Bootstrapper/claudius.sh $argv
end
```

Reload with `source ~/.config/fish/config.fish` or open a new terminal.

---

## Korn shell (ksh)

**Config file:** `~/.kshrc` or `$ENV` (often `~/.profile` if you use ksh as login shell)

```ksh
# Claudius — Claude Code + LM Studio bootstrapper (run: claudius)
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

Source the file or start a new shell.

---

## POSIX / sh (dash, ash, etc.)

Standard `sh` often does not support `alias` in non-interactive use. For an interactive shell, add to `~/.profile` or the file your sh reads (e.g. `~/.shrc` on some systems):

```sh
# Claudius — run: claudius
alias claudius='~/dev/Claudius-Bootstrapper/claudius.sh'
```

If your `sh` does not load aliases, run the script by path:

```sh
~/dev/Claudius-Bootstrapper/claudius.sh
```

---

## Summary

| Shell | Config file           | Reload / apply        |
|-------|------------------------|------------------------|
| Bash  | `~/.bashrc`            | `source ~/.bashrc`     |
| Zsh   | `~/.zshrc`             | `source ~/.zshrc`      |
| Fish  | `~/.config/fish/config.fish` | `source ~/.config/fish/config.fish` |
| Ksh   | `~/.kshrc` or `~/.profile` | `source ~/.kshrc` or new shell |
| sh    | `~/.profile` or `~/.shrc` | New login shell or `source` that file |

Use the path where you actually cloned the repo (e.g. `$HOME/dev/Claudius-Bootstrapper/claudius.sh`) if it differs from `~/dev/Claudius-Bootstrapper`.

**Options:** `claudius --init` — reset preferences (turn duration, keep session); also run after installing missing dependencies (first-time check). `claudius --purge` — clear saved Claude Code session data (all, or by age). `claudius --dry-run` / `--test` — test flow without writing config or starting Claude. If you chose not to keep session history, after Claude Code exits you get a menu to delete current session, purge by age, or skip.
