#!/usr/bin/env bash
# One-line bootstrap for Polban (پل‌بان).
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/silent4time/polban/main/get.sh | sudo bash
#
# Requires: root, git, and GitHub auth for the private repo
#   (GH_TOKEN env, or `gh auth login` already done on the server).
set -euo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "run as root"; exit 1; }

SRC="/opt/polban-src"
REPO="silent4time/polban"

export DEBIAN_FRONTEND=noninteractive
command -v git >/dev/null 2>&1 || { apt-get update -y; apt-get install -y git curl ca-certificates; }
command -v curl >/dev/null 2>&1 || apt-get install -y curl

clone_repo() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" "$SRC"
    return
  fi
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh repo clone "$REPO" "$SRC" -- --depth 1
    return
  fi
  echo "[x] Private repo needs GH_TOKEN or authenticated gh."
  echo "    Example: GH_TOKEN=... curl -fsSL ... | sudo bash"
  exit 1
}

if [[ -d "$SRC/.git" ]] && [[ "$(git --git-dir="$SRC/.git" config --get core.bare 2>/dev/null || echo false)" != "true" ]]; then
  # Existing checkout: discard local edits / mode changes and go to origin/main
  git -C "$SRC" config core.fileMode false
  git -C "$SRC" fetch --prune origin "+refs/heads/main:refs/remotes/origin/main"
  git -C "$SRC" checkout -q -B main origin/main
  git -C "$SRC" reset -q --hard origin/main
  git -C "$SRC" clean -fdq
else
  [[ -e "$SRC" ]] && mv "$SRC" "$SRC.old.$(date +%Y%m%d-%H%M%S)"
  rm -rf "$SRC"
  mkdir -p "$(dirname "$SRC")"
  clone_repo
fi

git -C "$SRC" config core.fileMode false
# No chmod here (it used to dirty the checkout); scripts are run via bash.
exec bash "$SRC/install.sh"
