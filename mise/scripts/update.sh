#!/usr/bin/env bash
# Runs every update task in order. Run by `mise run update` (mise/global.toml).
# sudo is asked for up front and kept fresh in the background, so the package upgrade (the
# second step, dnf or Homebrew casks) doesn't sit at a password prompt once you've walked away.
# mise runs tasks in this shell's session, so they share its sudo ticket.
set -euo pipefail

if [[ -t 0 ]] && command -v sudo >/dev/null 2>&1 &&
    { [[ "$(uname)" == Darwin ]] || command -v dnf >/dev/null 2>&1; }; then
    echo "==> sudo, for the system packages"
    sudo -v
    # Refreshes the ticket until this script ends (or sudo stops refreshing it)
    while sleep 50; do
        kill -0 $$ 2>/dev/null && sudo -n -v 2>/dev/null || exit
    done &
    keepalive=$!
    trap 'kill "$keepalive" 2>/dev/null || true' EXIT
fi

mise run update:dotfiles
mise run update:packages
mise run update:mise
mise run update:nvim
