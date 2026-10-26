#!/usr/bin/env bash
# Polban - install / update
#
#   sudo bash install.sh              open the management menu
#   sudo bash install.sh --install    fresh install / reconfigure (interactive)
#   sudo bash install.sh --update     update existing install, keep config.php (-y = same)
#   --dir PATH                        install dir (default /home/polban)
#
# --update only syncs files from THIS source tree; to fetch new code first use
#   sudo polban update
set -euo pipefail

TARGET="/home/polban"
SRC_DIR="/opt/polban-src"
MODE=""
BACKUP_DIR="/root/polban-backups"
TS="$(date +%Y%m%d-%H%M%S)"
WEB_USER="www-data"

say()  { echo "[*] $*"; }
ok()   { echo "[OK] $*"; }
die()  { echo "[x] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes|--update) MODE="update" ;;
    --install) MODE="install" ;;
    --menu) MODE="" ;;
    --dir) TARGET="${2:?--dir needs a path}"; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
TARGET="${TARGET%/}"

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root: sudo bash install.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
is_src() { [[ -f "$1/public/index.php" && -f "$1/lib/bootstrap.php" && -f "$1/VERSION" ]]; }
is_src "$SCRIPT_DIR" || die "run install.sh from the polban source tree"
SRC="$SCRIPT_DIR"

if [[ -z "$MODE" ]]; then
  PB_SRC="$SRC" PB_APP="$TARGET" exec bash "$SRC/bin/polban" menu
fi
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"

ask() { # ask "question" default [secret]
  local q="$1" def="${2:-}" secret="${3:-}" a=""
  [[ -r /dev/tty ]] || { echo "$def"; return; }
  if [[ -n "$secret" ]]; then
    read -r -s -p "$q " a </dev/tty || true; echo >/dev/tty
  else
    read -r -p "$q " a </dev/tty || true
  fi
  echo "${a:-$def}"
}

export DEBIAN_FRONTEND=noninteractive
command -v php   >/dev/null 2>&1 || { apt-get update -y; apt-get install -y php-cli php-curl; }
command -v curl  >/dev/null 2>&1 || apt-get install -y curl
command -v rsync >/dev/null 2>&1 || apt-get install -y rsync
php -m 2>/dev/null | grep -qi '^curl$' || apt-get install -y php-curl || true

if [[ "$MODE" == "update" ]]; then
  [[ -f "$TARGET/config.php" ]] || die "no $TARGET/config.php - not installed; use: sudo bash $SRC/install.sh --install"
  echo
  echo "  Polban $VERSION - update (config.php is kept)"
  echo "  Install dir: $TARGET"
  echo
else
  echo
  echo "  Polban $VERSION - fresh install"
  echo "  --------------------------------"
  TARGET="$(ask "Install dir [$TARGET]:" "$TARGET")"; TARGET="${TARGET%/}"
  BASE_URL="$(ask "Public base URL (e.g. https://bridge.example.com):" "")"
  [[ -n "$BASE_URL" ]] || die "base URL required"
  BASE_URL="${BASE_URL%/}"
  API_KEY="$(ask "API key (empty = generate):" "" secret)"
  [[ -n "$API_KEY" ]] || API_KEY="$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  ADMIN_PASS="$(ask "Web admin password:" "" secret)"
  [[ -n "$ADMIN_PASS" ]] || die "admin password required"
  ADMIN_PATH="pb-$(openssl rand -hex 4 2>/dev/null || head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  ALLOW="$(ask "First allowed panel origin (e.g. https://panel.example.com:8443, empty = later):" "")"
fi

mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
if [[ -f "$TARGET/config.php" ]]; then
  say "Backing up current install to $BACKUP_DIR/polban-$TS.tgz"
  tar -czf "$BACKUP_DIR/polban-$TS.tgz" -C "$(dirname "$TARGET")" "$(basename "$TARGET")" || true
fi

say "Copying files to $TARGET"
mkdir -p "$TARGET"
rsync -a --delete --exclude /config.php --exclude /storage --exclude /.git "$SRC/" "$TARGET/"
mkdir -p "$TARGET/storage/logs" "$TARGET/storage/sessions"

# Source checkout used by "polban update": ignore file-mode noise
if git -C "$SRC" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$SRC" config core.fileMode false || true
fi
# Installed from another tree and no checkout at $SRC_DIR yet: create one
if [[ "$(readlink -f "$SRC")" != "$(readlink -f "$SRC_DIR")" && ! -d "$SRC_DIR/.git" ]]; then
  url="$(git -C "$SRC" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -n "$url" ]] && git clone -q "$url" "$SRC_DIR" 2>/dev/null; then
    git -C "$SRC_DIR" config core.fileMode false
  else
    say "Note: no git checkout at $SRC_DIR; 'polban update' needs one (run get.sh)."
  fi
fi

if [[ "$MODE" == "install" ]]; then
  export PB_BASE_URL="$BASE_URL" PB_API_KEY="$API_KEY" PB_ADMIN_PASS="$ADMIN_PASS" PB_ADMIN_PATH="$ADMIN_PATH" PB_ALLOW="$ALLOW" PB_CFG="$TARGET/config.php"
  ( umask 077; php <<'PHP'
<?php
$allow = array();
$a = getenv('PB_ALLOW');
if ($a !== false && $a !== '') { $allow[] = rtrim($a, '/'); }
$cfg = array(
    'base_url'   => rtrim((string) getenv('PB_BASE_URL'), '/'),
    'api_key'    => (string) getenv('PB_API_KEY'),
    'admin_pass' => password_hash((string) getenv('PB_ADMIN_PASS'), PASSWORD_DEFAULT),
    'admin_path' => (string) getenv('PB_ADMIN_PATH'),
    'allowlist'  => $allow,
    'timeout'    => 60,
    'verify_ssl' => false,
);
file_put_contents(getenv('PB_CFG'), "<?php\nreturn " . var_export($cfg, true) . ";\n");
PHP
  )
  unset PB_API_KEY PB_ADMIN_PASS API_KEY ADMIN_PASS
else
  # Migration: upstream timeout must be at least 60s (only change made to config.php)
  PB_CFG="$TARGET/config.php" php -r '$f=getenv("PB_CFG"); $c=require $f; if (is_array($c) && (int)($c["timeout"] ?? 0) < 60) { $c["timeout"]=60; file_put_contents($f, "<?php\nreturn ".var_export($c,true).";\n"); echo "[*] config: timeout -> 60\n"; }'
fi

# Web panel (www-data) must be able to rewrite config.php
getent group "$WEB_USER" >/dev/null 2>&1 || WEB_USER="root"
chown "root:$WEB_USER" "$TARGET/config.php"
chmod 660 "$TARGET/config.php"
chown -R "$WEB_USER:$WEB_USER" "$TARGET/storage" 2>/dev/null || true

chmod 755 "$TARGET/bin/polban"
ln -sfn "$TARGET/bin/polban" /usr/local/bin/polban

cfg() { PB_CFG="$TARGET/config.php" PB_K="$1" php -r '$c=require getenv("PB_CFG"); echo (string)($c[getenv("PB_K")] ?? "");'; }
BASE_URL="$(cfg base_url)"; BASE_URL="${BASE_URL%/}"
ADMIN_PATH="$(cfg admin_path)"; ADMIN_PATH="${ADMIN_PATH#/}"; ADMIN_PATH="${ADMIN_PATH%/}"

# Apache vhost sample: fresh install only, never on update
if [[ "$MODE" == "install" && -d /etc/apache2/sites-available ]]; then
  HOST="$(php -r 'echo parse_url($argv[1], PHP_URL_HOST);' "$BASE_URL")"
  if [[ -n "$HOST" ]]; then
    VHOST="/etc/apache2/sites-available/polban.conf"
    cat > "$VHOST" <<APACHE
# Polban - enable: a2ensite polban && systemctl reload apache2
<VirtualHost *:80>
    ServerName $HOST
    DocumentRoot $TARGET/public
    <Directory $TARGET/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/polban-error.log
    CustomLog \${APACHE_LOG_DIR}/polban-access.log combined
</VirtualHost>
APACHE
    a2enmod rewrite >/dev/null 2>&1 || true
    say "Apache sample written: $VHOST (enable with: a2ensite polban)"
  fi
fi

echo
if [[ "$MODE" == "update" ]]; then ok "Updated to $VERSION (config.php kept)"; else ok "Installed Polban $VERSION"; fi
echo "  Service URL:  ${BASE_URL:-?}"
echo "  Health:       ${BASE_URL:-?}/v1/health"
echo "  Admin panel:  ${BASE_URL:-?}/${ADMIN_PATH:-?}/"
echo "  API key:      not shown; view with: sudo grep api_key $TARGET/config.php"
echo "  Manage:       sudo polban"
echo
