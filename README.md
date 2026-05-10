# dotfiles

Portable dev-environment configuration managed as a git repository. Clone on a
new machine, run one script, and you're set up.

## Quick start

```bash
git clone git@github.com:YOUR_USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install_configs.sh        # add --wsl on WSL
```

## What gets installed

### Symlinked dotfiles

| Repo file | Links to | Purpose |
|-----------|----------|---------|
| `bash_aliases` | `~/.bash_aliases` | Personal aliases |
| `bash_profile` | `~/.bash_profile` | Login shell bootstrap |
| `bashrc` | `~/.bashrc` | Shell config, prompt, history, PATH |
| `gitconfig` | `~/.gitconfig` | Git user, editor, credential helper |
| `profile` | `~/.profile` | Login shell PATH |
| `tmux.conf` | `~/.tmux.conf` | tmux keybindings, mouse, pi support |
| `vimrc` | `~/.vimrc` | Vim settings, plugins (vim-plug), ALE formatting |
| `ssh_config` | `~/.ssh/config` | SSH host aliases |

### Packages

Package lists are plain text files (one per line, no comments).

| File | Manager | How it's maintained |
|------|---------|---------------------|
| `apt-packages.txt` | apt | Hand-curated. Run `suggest_apt.sh` to discover candidates. |
| `npm-packages.txt` | npm (global, `~/.local` prefix) | Run `capture_packages.sh` to snapshot the current machine. |
| `pipx-packages.txt` | pipx | Run `capture_packages.sh` to snapshot the current machine. |

Also installed but not tracked as package lists:

| Tool | How |
|------|-----|
| Node.js 22.x | NodeSource setup script |
| Flutter SDK | Cloned to `~/development/flutter` (idempotent) |
| Vim plugins | vim-plug + `PlugInstall` |
| Ollama | Snap (`--classic`) |

### pi coding agent

Config lives in `pi-agent/`:

| File | Symlinked to |
|------|-------------|
| `settings.json` | `~/.pi/agent/settings.json` |
| `models.json` | `~/.pi/agent/models.json` |
| `auth.json` | Generated at install time from `secrets.age.txt` (not tracked) |

### WSL extras

| Config | Flag | What it does |
|--------|------|-------------|
| VS Code WSL remote settings | `--wsl` | `vscode/install.sh --apply` |
| Windows Terminal settings | `--wsl` | `windows-terminal/install.js --apply` |

## Scripts

### `install_configs.sh`

The bootstrap script for a new machine. Does everything in order:

1. Adds NodeSource repo, installs Node.js + apt packages
2. Sets npm prefix to `~/.local` (no sudo for global installs)
3. Installs npm and pipx packages from their `.txt` files
4. Installs snap packages (ollama)
5. Symlinks all dotfiles into `$HOME`
6. Bootstraps Flutter, vim-plug, Vim plugins
7. Installs pi agent config (decrypts secrets, symlinks configs)
8. Applies WSL-specific settings if `--wsl` is passed

### `capture_packages.sh`

Run after adding or removing global npm/pipx packages. Reads the current
state and writes `npm-packages.txt` and `pipx-packages.txt`. Commit the
updated files.

```bash
./capture_packages.sh
git add npm-packages.txt pipx-packages.txt
git commit -m "update package lists"
```

### `suggest_apt.sh`

Mines `~/.bash_history` for `apt install` commands, verifies each candidate
is a real installed package, and shows which ones are already in
`apt-packages.txt` and which aren't.

```bash
./suggest_apt.sh
# Already in apt-packages.txt:
#   ✓  age
#   ✓  vim-gtk3
#
# New (not yet in apt-packages.txt):
#   ✦  ffmpeg
#   ✦  zip
#
# To add them, append to apt-packages.txt and run capture_packages.sh.
```

Review the suggestions, append what you want to `apt-packages.txt`, and commit.

## Secrets

Secrets (API keys) are stored in two places, neither committed:

| File | Purpose |
|------|---------|
| `.secrets` | Sourced by `bashrc` at shell startup. Sets env vars like `GEMINI_API_KEY`. |
| `pi-agent/secrets.age.txt` | age-encrypted with your SSH key. Decrypted at install time to produce `~/.pi/agent/auth.json`. |

Env vars are copied manually to `.secrets`. The pi auth file is updated by
re-encrypting `secrets.age.txt`:

```bash
age -R ~/.ssh/id_github_key.pub -o pi-agent/secrets.age.txt secrets.age.txt
```
