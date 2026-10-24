#!/usr/bin/env bash
# Updates Neovim, its plugins and Mason tools (skipped where Neovim isn't installed).
# Run by `mise run update:nvim` (mise/global.toml), from the dotfiles folder.
set -euo pipefail

echo "==> Updating Neovim, its plugins and Mason tools"
if command -v nvim >/dev/null 2>&1 && [[ -x nvim-config/install.sh ]]; then
    nvim-config/install.sh --update
else
    echo "nvim: not installed, skipped"
fi
