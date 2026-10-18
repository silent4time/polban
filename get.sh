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
    git clone --depth 1 "https://${GH_TOKEN}@github.com/${REPO}.git" "$SRC"
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

if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" pull --ff-only
else
  rm -rf "$SRC"
  mkdir -p "$(dirname "$SRC")"
  clone_repo
fi

chmod +x "$SRC/install.sh" "$SRC/bin/polban" "$SRC/get.sh"
exec bash "$SRC/install.sh"
