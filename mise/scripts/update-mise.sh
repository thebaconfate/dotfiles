#!/usr/bin/env bash
# Updates mise itself and the tools it manages, keeping global npm packages.
# Run by `mise run update:mise` (mise/global.toml).
set -euo pipefail

echo "==> Updating mise and its tools"
mise self-update --yes || echo "mise: no self-update (installed by a package manager?), skipped"

# Global npm packages belong to one exact Node version. mise gives a new Node the ones in
# ~/.default-npm-packages, but not the rest (from a private registry, a tarball, ...), so
# those are packed from the old Node, which `mise upgrade` keeps for a day, and installed again.
old="$(mise where node 2>/dev/null || true)"
mise upgrade
new="$(mise where node 2>/dev/null || true)"
if [[ -n "$old" && -n "$new" && "$old" != "$new" && -d "$old/lib/node_modules" ]]; then
    tmp="$(mktemp -d)"
    for dir in "$old"/lib/node_modules/[!@]* "$old"/lib/node_modules/@*/*; do
        [[ -d "$dir" ]] || continue
        name="${dir#"$old"/lib/node_modules/}"
        [[ "$name" == npm || "$name" == corepack || -d "$new/lib/node_modules/$name" ]] && continue
        echo "node: carrying $name over from $(basename "$old")"
        (cd "$tmp" && "$new/bin/npm" pack --silent "$dir" >/dev/null)
    done
    shopt -s nullglob
    packed=("$tmp"/*.tgz)
    if ((${#packed[@]})); then "$new/bin/npm" install -g "${packed[@]}"; fi
    rm -rf "$tmp"
fi
