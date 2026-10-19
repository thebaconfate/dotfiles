# dotfiles

A repository containing all my dotfiles, and a script that sets up a new macOS or Fedora
machine with them.

## New machine

```sh
curl -fsSL https://raw.githubusercontent.com/thebaconfate/dotfiles/main/bootstrap.sh | bash
```

`bootstrap.sh` gets the machine ready for SSH before cloning anything:

1. Installs git and the GitHub CLI (`gh`), through Homebrew on macOS or dnf on Fedora.
2. Creates `~/.ssh/id_ed25519` if it's missing, logs in to GitHub in the browser, and uploads
   the key as an authentication and a signing key.
3. Sets git's name and email, suggesting your GitHub name and verified emails, and turns on
   SSH commit signing.
4. Clones this repo over SSH into `~/.dotfiles` (or `$DOTFILES_DIR`), then runs `install.sh`.

Declining the SSH step clones over HTTPS without signing; re-running `bootstrap.sh` later
sets SSH up and switches the remotes over. Arguments go to `install.sh`:
`curl ... | bash -s -- --yes`.

## install.sh

On a machine that already has the repo, run `install.sh` directly
(`~/.dotfiles/install.sh --dry-run` first to see what it would do). Without an SSH key it
clones the submodules over HTTPS, keeping their SSH remotes. It asks before each part, and is
safe to re-run:

1. **Tools**: everything in `packages/Brewfile` (macOS) or `packages/fedora.txt` (Fedora,
   asked per group, so the Surface can skip `[gaming]`). On Fedora also a system upgrade,
   the hostname, RPM Fusion, the Brave and Docker repos, and zsh as the login shell.
2. **mise + Node and Python**: links `mise/global.toml` as the global mise config, then installs what it pins. The Neovim config needs Node for its formatters.
3. **CodeNewRoman Nerd Font**, into `~/Library/Fonts` or `~/.local/share/fonts`.
4. **Configs**: each submodule you pick, set up by its own `install.sh`. Your answers are
   remembered in `.git/config`, so later runs only ask about new configs.
5. **Hardware** (Fedora): the NVIDIA driver when `lspci` finds an NVIDIA GPU, the
   linux-surface kernel on a Microsoft Surface.

Whatever is left to do by hand is listed at the end of the run.

| Option | |
|---|---|
| `--dry-run` | only show what would happen |
| `--yes` | take every default without asking |
| `--only zsh,nvim` | set up only these configs, skip the other steps |
| `--reconfigure` | ask again about configs you already chose |

## Configs

| Folder | Default | |
|---|---|---|
| `zsh-config` | yes | oh-my-zsh, fzf, zoxide |
| `tmux-config` | yes | tmux, TPM and plugins |
| `nvim-config` | yes | Neovim, plugins, Mason tools |
| `alacritty-config` | yes | Alacritty |
| `ideavim-config` | no | IdeaVim, for JetBrains IDEs |
| `pwsh-config` | not offered | Windows only; kept for a move back |

## Layout

```
bootstrap.sh        first run on a new machine: git, SSH, clone, then install.sh
install.sh          sets up a cloned repo (macOS + Linux)
lib/common.sh       helpers shared by the scripts below
os/macos.sh         Homebrew + packages/Brewfile
os/fedora.sh        dnf, repos and packages/fedora.txt
hardware/nvidia.sh  NVIDIA driver (RPM Fusion, Secure Boot signing)
hardware/surface.sh linux-surface kernel, touch and pen
*-config/           the configs, as submodules
```

The scripts under `os/` and `hardware/` also run on their own, for example
`./hardware/nvidia.sh` after swapping in a GPU.

## By hand

### Git and SSH

`bootstrap.sh` does all of this; by hand it's:

```sh
git config --global user.name "Your name"
git config --global user.email "you@example.com"
git config --global core.editor nvim
ssh-keygen -t ed25519 -C "you@example.com"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub   # add it to GitHub, as an authentication and a signing key
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

### Spotify on Fedora

`install.sh` installs `lpf-spotify-client` with the `[apps]` group. lpf then builds the
actual package:

```sh
lpf approve spotify-client                 # then log out and back in
sudo -u pkg-build lpf build spotify-client # takes up to 5 minutes
sudo dnf install /var/lib/lpf/rpms/spotify-client/spotify-client-*.rpm
```

### Alacritty on macOS

Homebrew disabled the Alacritty cask on 2026-09-01, so install the `.dmg` from
[the releases](https://github.com/alacritty/alacritty/releases).

### Reboots after the hardware step

- **NVIDIA with Secure Boot**: at the reboot, choose *Enroll MOK* in the blue MOK manager
  and enter the password you set. Afterwards `nvidia-smi` should list the GPU.
- **Surface**: the same MOK screen, with the password `surface` (typed on QWERTY).
  Afterwards `uname -r` should contain `surface`.
