#!/usr/bin/env bash
# Pulls the dotfiles, and each config on the branch it's on (fast-forward only).
# Run by `mise run update:dotfiles` (mise/global.toml), from the dotfiles folder.
set -euo pipefail

echo "==> Pulling the dotfiles and configs"
git pull --ff-only || echo "dotfiles: not pulled (diverged from upstream?)"
# On their own branches, like install.sh does: `git submodule update` would detach them
# shellcheck disable=SC2016 # $sm_path is for the shell git runs per submodule
git submodule foreach --quiet 'git pull --ff-only --quiet || echo "$sm_path: not pulled (no upstream, or diverged)"'
