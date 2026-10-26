#!/usr/bin/env bash
# Polban (پل‌بان) — install / reconfigure
#
# One-liner (private repo; needs gh auth or a zip):
#   curl -fsSL https://raw.githubusercontent.com/silent4time/polban/main/get.sh | sudo bash
#
# Or from a checkout:
#   sudo bash install.sh
#
# Options: -y   non-interactive defaults where possible
set -euo pipefail

TARGET="/home/polban"
SRC_DIR="/opt/polban-src"
ASSUME_YES=0
BACKUP_DIR="/root/polban-backups"
TS="$(date +%Y%m%d-%H%M%S)"
WEB_USER="www-data"

say()  { echo "[*] $*"; }
ok()   { echo "[OK] $*"; }
die()  { echo "[x] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --dir) TARGET="${2:?}"; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root: sudo bash install.sh"

ask() {
  local q="$1" def="${2:-}" a=""
  if [[ $ASSUME_YES -eq 1 || ! -r /dev/tty ]]; then echo "$def"; return; fi
  read -r -p "$q " a </dev/tty || true
  echo "${a:-$def}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
is_src() { [[ -f "$1/public/index.php" && -f "$1/lib/bootstrap.php" && -f "$1/VERSION" ]]; }
is_src "$SCRIPT_DIR" || die "run from polban source tree"
SRC="$SCRIPT_DIR"
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"

command -v php >/dev/null 2>&1 || { apt-get update -y; apt-get install -y php-cli php-curl php-sqlite3; }
command -v curl >/dev/null 2>&1 || apt-get install -y curl
php -m 2>/dev/null | grep -qi curl || apt-get install -y php-curl

echo
echo "  پل‌بان (Polban) $VERSION"
echo "  --------------------------------"
echo "  مسیر نصب: $TARGET"
echo

TARGET="$(ask "مسیر نصب [$TARGET]:" "$TARGET")"

# Update mode: existing install + -y keeps config.php, only syncs code and fixes permissions
UPDATE=0
if [[ $ASSUME_YES -eq 1 && -f "$TARGET/config.php" ]]; then
  UPDATE=1
  say "حالت به‌روزرسانی: config.php فعلی حفظ می‌شود."
fi

if [[ $UPDATE -eq 0 ]]; then
BASE_URL="$(ask "آدرس عمومی پل‌بان (مثل https://bridge.example.com):" "")"
[[ -n "$BASE_URL" ]] || die "base URL required"
BASE_URL="${BASE_URL%/}"

API_KEY="$(ask "کلید API (خالی = ساخت خودکار):" "")"
[[ -z "$API_KEY" ]] && API_KEY="$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p)"

ADMIN_PASS="$(ask "رمز پنل مدیریت وب:" "")"
[[ -n "$ADMIN_PASS" ]] || die "admin password required"
ADMIN_PATH="pb-$(openssl rand -hex 4 2>/dev/null || echo a1b2c3d4)"

ALLOW="$(ask "مبدأ مجاز پنل اول (مثل https://panel.example.com:8443 ، خالی = بعداً):" "")"
fi

mkdir -p "$BACKUP_DIR"
if [[ -d "$TARGET" && -f "$TARGET/config.php" ]]; then
  say "بکاپ نصب قبلی…"
  tar -czf "$BACKUP_DIR/polban-$TS.tgz" -C "$(dirname "$TARGET")" "$(basename "$TARGET")" || true
fi

say "کپی فایل‌ها…"
mkdir -p "$TARGET" "$SRC_DIR"
rsync -a --delete --exclude config.php --exclude storage "$SRC/" "$TARGET/"
mkdir -p "$TARGET/storage/logs" "$TARGET/storage/sessions"
touch "$TARGET/storage/logs/.gitkeep" "$TARGET/storage/sessions/.gitkeep"

# Keep a source checkout pointer for updates
if [[ "$(readlink -f "$SRC")" != "$(readlink -f "$SRC_DIR")" ]]; then
  if [[ -d "$SRC/.git" ]]; then
    if [[ ! -d "$SRC_DIR/.git" ]]; then
      git clone --mirror "$SRC/.git" "$SRC_DIR/.git" 2>/dev/null || rsync -a "$SRC/" "$SRC_DIR/"
    fi
    # Prefer live clone at SRC_DIR for pull
    if [[ ! -f "$SRC_DIR/install.sh" ]]; then
      rsync -a --exclude storage "$SRC/" "$SRC_DIR/"
    else
      rsync -a --exclude storage --exclude config.php "$SRC/" "$SRC_DIR/"
    fi
  else
    rsync -a --exclude storage --exclude config.php "$SRC/" "$SRC_DIR/"
  fi
fi

if [[ $UPDATE -eq 0 ]]; then
export PB_BASE_URL="$BASE_URL" PB_API_KEY="$API_KEY" PB_ADMIN_PASS="$ADMIN_PASS" PB_ADMIN_PATH="$ADMIN_PATH" PB_ALLOW="$ALLOW" PB_CFG="$TARGET/config.php"
php <<'PHP'
<?php
$allow = array();
$a = getenv('PB_ALLOW');
if ($a !== false && $a !== '') {
    $allow[] = rtrim($a, '/');
}
$cfg = array(
    'base_url'   => rtrim((string) getenv('PB_BASE_URL'), '/'),
    'api_key'    => (string) getenv('PB_API_KEY'),
    'admin_pass' => password_hash((string) getenv('PB_ADMIN_PASS'), PASSWORD_DEFAULT),
    'admin_path' => (string) getenv('PB_ADMIN_PATH'),
    'allowlist'  => $allow,
    'timeout'    => 60,
    'verify_ssl' => false,
);
$file = getenv('PB_CFG');
file_put_contents($file, "<?php\nreturn " . var_export($cfg, true) . ";\n");
PHP
else
  # Migrate: raise old default upstream timeout to 60s
  PB_CFG="$TARGET/config.php" php -r '$f=getenv("PB_CFG"); $c=require $f; if ((int)($c["timeout"]??25) < 60) { $c["timeout"]=60; file_put_contents($f, "<?php\nreturn ".var_export($c,true).";\n"); echo "[*] timeout -> 60\n"; }'
fi
# Web panel (www-data) must be able to rewrite config.php
chown "root:$WEB_USER" "$TARGET/config.php"
chmod 660 "$TARGET/config.php"
chown -R "$WEB_USER:$WEB_USER" "$TARGET/storage" 2>/dev/null || true

install -m 755 "$TARGET/bin/polban" /usr/local/bin/polban
# rewrite APP discovery is fine via readlink

# Update mode: read display values from existing config (never the API key)
if [[ $UPDATE -eq 1 ]]; then
  BASE_URL="$(PB_CFG="$TARGET/config.php" php -r '$c=require getenv("PB_CFG"); echo rtrim((string)($c["base_url"]??""),"/");')"
  ADMIN_PATH="$(PB_CFG="$TARGET/config.php" php -r '$c=require getenv("PB_CFG"); echo trim((string)($c["admin_path"]??""),"/");')"
fi

# Apache vhost hint (fresh install only; never rewrite on update)
if [[ $UPDATE -eq 0 && -d /etc/apache2/sites-available ]]; then
  HOST="$(php -r 'echo parse_url($argv[1], PHP_URL_HOST);' "$BASE_URL")"
  if [[ -n "$HOST" ]]; then
    VHOST="/etc/apache2/sites-available/polban.conf"
    cat > "$VHOST" <<APACHE
# Polban — enable: a2ensite polban && systemctl reload apache2
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
    say "نمونهٔ Apache نوشته شد: $VHOST (در صورت نیاز a2ensite polban)"
  fi
fi

if [[ $UPDATE -eq 1 ]]; then
  ok "به‌روزرسانی به $VERSION تمام شد (config.php حفظ شد)"
  echo
  echo "  آدرس سرویس:   ${BASE_URL:-?}"
  echo "  سلامت:         ${BASE_URL:-?}/v1/health"
  echo "  پنل مدیریت:    ${BASE_URL:-?}/${ADMIN_PATH:-?}/"
  echo "  فرمان مدیریت:  sudo polban"
  echo
  exit 0
fi

ok "نصب تمام شد"
echo
echo "  آدرس سرویس:   $BASE_URL"
echo "  سلامت:         $BASE_URL/v1/health"
echo "  پنل مدیریت:    $BASE_URL/$ADMIN_PATH/"
echo "  کلید API:      $API_KEY"
echo "  فرمان مدیریت:  sudo polban"
echo
echo "  این کلید را در افزونهٔ ابزار شبکه (تنظیمات پل‌بان) بگذارید."
echo
