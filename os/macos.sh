#!/usr/bin/env bash
# macOS tools: Homebrew, then everything in packages/Brewfile. Run by install.sh, or on its
# own (./os/macos.sh). Safe to re-run: brew bundle skips what's installed and upgrades the rest.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/common.sh
. "$DOTFILES/lib/common.sh"
BREWFILE="$DOTFILES/packages/Brewfile"

load_brew() {
    local brew_bin
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$brew_bin" ]]; then
            eval "$("$brew_bin" shellenv)"
            return 0
        fi
    done
    return 1
}

# 1. Homebrew. Its installer also brings the Xcode command line tools (git, make, a compiler).
has brew || load_brew || true
if has brew; then
    info "homebrew: already installed"
elif ((DRY_RUN)); then
    info "homebrew: would install with the official installer"
else
    info "homebrew: installing (asks for your password)"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew
fi

# 2. The Brewfile
if ! has brew; then
    info "brewfile: would install everything in packages/Brewfile"
elif ((DRY_RUN)); then
    info "brewfile: what's missing or outdated in packages/Brewfile:"
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file="$BREWFILE" --verbose | sed 's/^/      /' || true
else
    info "brewfile: installing and upgrading packages/Brewfile"
    brew bundle install --file="$BREWFILE"
fi

# 3. Alacritty. Homebrew disabled its cask on 2026-09-01 (the app isn't notarised for
#    Gatekeeper), so it's no longer in the Brewfile.
if [[ -d /Applications/Alacritty.app ]]; then
    info "alacritty: already installed"
else
    info "alacritty: not installed; Homebrew no longer has it"
    note "Install Alacritty from https://github.com/alacritty/alacritty/releases (the .dmg)"
fi
