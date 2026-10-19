#!/usr/bin/env bash
# Sets up a macOS or Fedora machine from these dotfiles, asking before each part:
#   1. the usual tools: packages/Brewfile on macOS, packages/fedora.txt on Fedora
#   2. mise with Node and Python (mise/global.toml), which the Neovim config needs for its
#      formatters
#   3. the CodeNewRoman Nerd Font
#   4. the configs (submodules) you pick, each set up by its own install.sh
#   5. drivers for hardware it finds: an NVIDIA GPU, a Microsoft Surface (Linux only)
# Safe to re-run: what's already in place is skipped, and config choices are remembered in
# .git/config (submodule.<name>.active), so the next run only asks about new ones.
# Written for bash 3.2, the version macOS ships, since a fresh Mac has nothing newer yet.
#
#   ./install.sh                  ask, then install
#   ./install.sh --dry-run        only show what would happen
#   ./install.sh --yes            take every default without asking
#   ./install.sh --only zsh,nvim  set up only these configs and skip the other steps
#   ./install.sh --reconfigure    ask again about configs you already chose
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
ASSUME_YES=0
RECONFIGURE=0
ONLY=""

usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"; }

while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --yes | -y) ASSUME_YES=1 ;;
        --reconfigure) RECONFIGURE=1 ;;
        --only)
            ONLY="${2:?--only needs a list, like --only zsh,tmux}"
            shift
            ;;
        --only=*) ONLY="${1#--only=}" ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1 (see --help)" >&2
            exit 1
            ;;
    esac
    shift
done

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT
export DOTFILES DRY_RUN ASSUME_YES NOTES_FILE

# shellcheck source=lib/common.sh
. "$DOTFILES/lib/common.sh"

case "$(uname -s)" in
    Darwin) OS=macos ;;
    Linux)
        # shellcheck disable=SC1091
        distro="$(. /etc/os-release 2>/dev/null && echo "${ID:-}")"
        if [[ "$distro" == fedora ]]; then OS=fedora; else OS="linux${distro:+ ($distro)}"; fi
        ;;
    *) OS="$(uname -s)" ;;
esac
((DRY_RUN)) && echo "Dry run: nothing is installed or changed."
echo "Setting up $OS$(is_wsl && echo ' under WSL' || true) from $DOTFILES"

# 1. Tools ----------------------------------------------------------------------------------

step_tools() {
    log "Tools"
    case "$OS" in
        macos | fedora)
            local list=packages/fedora.txt
            [[ "$OS" == macos ]] && list=packages/Brewfile
            if ask "Install your usual tools ($list)?" y; then
                bash "$DOTFILES/os/$OS.sh"
            fi
            ;;
        *) info "no tool list for $OS yet, skipping" ;;
    esac
}

# 2. mise + Node and Python -----------------------------------------------------------------

# Without mise, the command line tools in mise/global.toml come from the package manager.
# Fedora has no pnpm, cargo-binstall or colima package, and kubectl only under versioned names.
tools_without_mise() {
    case "$OS" in
        macos)
            info "tools: installing jq, kubectl, pnpm, cargo-binstall, maven and colima with Homebrew"
            run brew install jq kubernetes-cli pnpm cargo-binstall maven colima
            ;;
        fedora)
            info "tools: installing jq and maven with dnf (pnpm, cargo-binstall, kubectl, colima: by hand)"
            run sudo dnf install -y jq maven
            ;;
        *) info "tools: no package list for $OS; install jq, kubectl, pnpm, cargo-binstall, maven and colima by hand" ;;
    esac
}

step_runtimes() {
    log "mise + Node and Python"
    if ! ask "Install mise, Node, Python and the command line tools in mise/global.toml?" y; then
        tools_without_mise
        return 0
    fi
    export PATH="$HOME/.local/bin:$PATH"
    if has mise; then
        info "mise: already installed"
    else
        info "mise: installing to ~/.local/bin"
        run sh -c 'curl -fsSL https://mise.run | sh'
    fi
    if ! has mise; then
        info "node + python: would install them through mise"
        return 0
    fi
    # The global config comes from the repo (mise/global.toml), so every machine gets the same
    # Node and Python; an existing one is moved aside to config.toml.bak
    local mise_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
    run mkdir -p "$mise_dir"
    link "$DOTFILES/mise/global.toml" "$mise_dir/config.toml"
    info "node, python and the command line tools: installing the versions in mise/global.toml"
    run mise install
    # Later steps run without `mise activate`, so they find node and npm through the shims
    export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH"
}

# 3. Nerd Font ------------------------------------------------------------------------------

FONT=CodeNewRoman

step_font() {
    log "Nerd Font ($FONT)"
    if is_wsl; then
        info "WSL: the font belongs on the Windows side, skipping"
        return 0
    fi
    local dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
    [[ "$OS" == macos ]] && dir="$HOME/Library/Fonts"
    if compgen -G "$dir/${FONT}NerdFont*" >/dev/null; then
        info "already installed in $dir"
        return 0
    fi
    ask "Install the $FONT Nerd Font into $dir?" y || return 0
    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$FONT.zip"
    if ((DRY_RUN)); then
        info "would download $url and copy its fonts into $dir"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/font.zip" "$url"
    unzip -qo "$tmp/font.zip" -d "$tmp/font"
    mkdir -p "$dir"
    find "$tmp/font" -type f \( -name '*.otf' -o -name '*.ttf' \) -exec cp {} "$dir/" \;
    rm -rf "$tmp"
    has fc-cache && fc-cache -f "$dir" >/dev/null
    info "installed into $dir"
}

# 4. Configs --------------------------------------------------------------------------------

# Whether a config is offered on this machine, and the answer when you just press Enter
config_default() {
    case "$1" in
        pwsh-config) echo skip ;; # Windows only: kept in the repo for a move back, never offered here
        ideavim-config) echo n ;; # only useful with a JetBrains IDE
        *) echo y ;;
    esac
}

# --only accepts the folder name (zsh-config), the short name (zsh) or the submodule name
in_only_list() {
    local path="$1" name="$2" item
    for item in ${ONLY//,/ }; do
        [[ "$item" == "$path" || "$item-config" == "$path" || "$item" == "$name" ]] && return 0
    done
    return 1
}

# link <file in the repo> <destination>: moves a real file aside, re-points an old link
link() {
    local src="$1" dest="$2"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
        info "$dest: already linked"
        return 0
    fi
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        info "$dest: moving the existing file to $dest.bak"
        run mv "$dest" "$dest.bak"
    fi
    info "$dest: linking to $src"
    run ln -sfn "$src" "$dest"
}

# The submodule URLs are SSH (git@github.com:...), which a fresh machine without a key can't
# clone. Then clone over HTTPS instead, for that one command: the submodule keeps its SSH
# remote, so pushing works once the key is set up.
GITHUB_SSH=""
github_ssh_ok() {
    if [[ -z "$GITHUB_SSH" ]]; then
        local out
        out="$(ssh -T -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
            git@github.com 2>&1 || true)"
        [[ "$out" == *"successfully authenticated"* ]] && GITHUB_SSH=yes || GITHUB_SSH=no
    fi
    [[ "$GITHUB_SSH" == yes ]]
}

setup_config() {
    local path="$1" dir="$DOTFILES/$1"
    # A checkout that already exists stays on its branch: `submodule update` would detach it
    if [[ -e "$dir/.git" ]]; then
        info "already checked out, left on its current branch"
    elif github_ssh_ok; then
        run git -C "$DOTFILES" submodule update --init -- "$path"
    else
        info "no SSH access to GitHub yet, cloning over HTTPS"
        run git -C "$DOTFILES" -c "url.https://github.com/.insteadOf=git@github.com:" \
            submodule update --init -- "$path"
    fi
    if [[ -x "$dir/install.sh" ]]; then
        if ((!DRY_RUN)); then
            "$dir/install.sh"
        elif grep -q -- '--dry-run' "$dir/install.sh"; then
            "$dir/install.sh" --dry-run
        else
            info "would run $path/install.sh (it has no --dry-run)"
        fi
        return 0
    fi
    # Configs without an install.sh of their own
    case "$path" in
        ideavim-config) link "$dir/.ideavimrc" "$HOME/.ideavimrc" ;;
        *)
            if [[ -e "$dir/.git" ]] || ((!DRY_RUN)); then
                info "no install.sh; see $path/README.md to set it up"
                note "Set up $path by hand: it has no install.sh"
            else
                info "would run its install.sh, if it has one"
            fi
            ;;
    esac
}

step_configs() {
    log "Configs"
    local key path name default saved
    # The list comes in on fd 3, so prompts and the installers keep the terminal on stdin
    while read -r key path <&3; do
        name="${key#submodule.}"
        name="${name%.path}"
        default="$(config_default "$path")"
        if [[ -n "$ONLY" ]]; then
            in_only_list "$path" "$name" || continue
        elif [[ "$default" == skip ]]; then
            continue
        else
            saved="$(git -C "$DOTFILES" config --get "submodule.$name.active" || true)"
            if [[ -n "$saved" ]] && ((!RECONFIGURE)); then
                if [[ "$saved" != true ]]; then
                    info "$path: skipped (chosen before; --reconfigure to change)"
                    continue
                fi
            elif ask "Set up $path?" "$default"; then
                run git -C "$DOTFILES" config "submodule.$name.active" true
            else
                run git -C "$DOTFILES" config "submodule.$name.active" false
                continue
            fi
        fi
        log "Config: $path"
        setup_config "$path"
    done 3< <(git config -f "$DOTFILES/.gitmodules" --get-regexp '^submodule\..*\.path$')
}

# 5. Hardware -------------------------------------------------------------------------------

step_hardware() {
    log "Hardware"
    if [[ "$OS" != fedora ]] || is_wsl; then
        info "nothing to do on $OS$(is_wsl && echo ' under WSL' || true)"
        return 0
    fi
    local found=0 gpu vendor product
    gpu="$(lspci -d 10de: 2>/dev/null | grep -Ei 'vga|3d' | head -n 1 || true)"
    if [[ -n "$gpu" ]]; then
        found=1
        info "NVIDIA GPU: ${gpu#*: }"
        if ask "Install the NVIDIA driver?" y; then
            bash "$DOTFILES/hardware/nvidia.sh"
        fi
    fi
    vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    if [[ "$vendor" == "Microsoft Corporation" && "$product" == Surface* ]]; then
        found=1
        info "Microsoft $product"
        if ask "Install the linux-surface kernel (touchscreen, pen, cameras)?" y; then
            bash "$DOTFILES/hardware/surface.sh"
        fi
    fi
    ((found)) || info "no NVIDIA GPU or Surface found"
}

# -------------------------------------------------------------------------------------------

if [[ -z "$ONLY" ]]; then
    step_tools
    step_runtimes
    step_font
fi
step_configs
[[ -n "$ONLY" ]] || step_hardware

if [[ -z "$(git config --global user.email || true)" ]]; then
    note "Set your git identity and SSH key: run bootstrap.sh, or see the README, 'Git and SSH'"
fi

log "Done"
if [[ -s "$NOTES_FILE" ]]; then
    echo "Still to do by hand:"
    while read -r line; do echo "  - $line"; done <"$NOTES_FILE"
fi
echo "Open a new terminal (or run: exec zsh) to pick everything up."
