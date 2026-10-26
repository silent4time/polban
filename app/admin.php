<?php
if (!defined('PB_ROOT')) {
    exit;
}
$cfg = pb_config();
session_name('polban_admin');
session_start();

$path = '/' . trim((string) $cfg['admin_path'], '/');
$base = rtrim((string) ($cfg['base_url'] ?: ''), '/');

function pb_admin_ok() {
    return !empty($_SESSION['pb_admin']);
}

if (isset($_GET['logout'])) {
    $_SESSION = array();
    session_destroy();
    header('Location: ' . $path . '/');
    exit;
}

$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['password'])) {
    $hash = (string) $cfg['admin_pass'];
    if ($hash !== '' && password_verify((string) $_POST['password'], $hash)) {
        $_SESSION['pb_admin'] = 1;
        header('Location: ' . $path . '/');
        exit;
    }
    $err = 'رمز نادرست است.';
}

if (pb_admin_ok() && $_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_allow'])) {
    $lines = preg_split('/\r\n|\r|\n/', (string) $_POST['allowlist']);
    $list = array();
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || strpos($line, '#') === 0) {
            continue;
        }
        $o = pb_origin($line);
        if ($o !== '') {
            $list[] = $o;
        }
    }
    $cfg['allowlist'] = array_values(array_unique($list));
    if (!empty($_POST['regen_key'])) {
        $cfg['api_key'] = bin2hex(random_bytes(24));
    }
    $export = "<?php\nreturn " . var_export($cfg, true) . ";\n";
    $cfg_file = PB_ROOT . '/config.php';
    if (@file_put_contents($cfg_file, $export, LOCK_EX) === false) {
        pb_log('admin save FAILED: config.php not writable');
        header('Location: ' . $path . '/?save_error=1');
        exit;
    }
    if (function_exists('opcache_invalidate')) {
        @opcache_invalidate($cfg_file, true);
    }
    pb_log('admin updated allowlist/key');
    header('Location: ' . $path . '/?saved=1');
    exit;
}

header('Content-Type: text/html; charset=utf-8');
?><!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>پل‌بان</title>
<style>
:root{--y:#F5C518;--b:#0D0D0D;--g:#1A1A1A;--m:#6E6E6E;--f:#F4F4F4}
*{box-sizing:border-box}body{margin:0;font-family:Tahoma,Arial,sans-serif;background:linear-gradient(160deg,#0D0D0D,#1A1A1A 40%,#2C2C2C);color:#fff;min-height:100vh}
.wrap{max-width:720px;margin:0 auto;padding:28px 16px}
.card{background:rgba(255,255,255,.04);border:1px solid rgba(245,197,24,.25);border-radius:14px;padding:22px}
h1{margin:0 0 8px;font-size:1.4rem}h1 span{color:var(--y)}
.muted{color:var(--m);font-size:.9rem;margin-bottom:18px}
label{display:block;margin:12px 0 6px;font-size:.85rem;color:#ddd}
input,textarea{width:100%;padding:10px 12px;border-radius:8px;border:1px solid #333;background:#111;color:#fff;font:inherit}
textarea{min-height:140px;direction:ltr;text-align:left}
button,.btn{display:inline-block;margin-top:14px;background:var(--y);color:#000;border:0;border-radius:8px;padding:10px 16px;font-weight:700;cursor:pointer;text-decoration:none}
.ok{background:#143d1a;border:1px solid #2a7;color:#cfc;padding:10px;border-radius:8px;margin-bottom:12px}
.err{background:#3d1414;border:1px solid #a44;color:#fcc;padding:10px;border-radius:8px;margin-bottom:12px}
code{direction:ltr;display:inline-block;background:#000;padding:2px 6px;border-radius:4px}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
</style>
</head>
<body><div class="wrap">
<?php if (!pb_admin_ok()): ?>
<div class="card">
<h1>ورود به <span>پل‌بان</span></h1>
<p class="muted">نسخه <?= htmlspecialchars(PB_VERSION) ?></p>
<?php if ($err): ?><div class="err"><?= htmlspecialchars($err) ?></div><?php endif; ?>
<form method="post">
<label>رمز مدیریت</label>
<input type="password" name="password" required autofocus>
<button type="submit">ورود</button>
</form>
</div>
<?php else:
$allow = implode("\n", (array) $cfg['allowlist']);
?>
<div class="card">
<div class="row" style="justify-content:space-between">
<h1>پنل <span>پل‌بان</span></h1>
<a class="btn" href="?logout=1" style="background:#333;color:#fff">خروج</a>
</div>
<p class="muted">نسخه <?= htmlspecialchars(PB_VERSION) ?> — سلامت: <code>/v1/health</code> — پروکسی: <code>POST /v1/proxy</code></p>
<?php if (!empty($_GET['saved'])): ?><div class="ok">ذخیره شد.</div><?php endif; ?>
<?php if (!empty($_GET['save_error'])): ?><div class="err">ذخیره نشد: فایل config.php قابل نوشتن نیست. روی سرور sudo polban و گزینهٔ ۲ (به‌روزرسانی) را اجرا کنید.</div><?php endif; ?>
<p>کلید API فعلی: <code><?= htmlspecialchars(substr((string)$cfg['api_key'],0,8)) ?>…</code></p>
<form method="post">
<input type="hidden" name="save_allow" value="1">
<label>مبدأهای مجاز پنل (هر خط یک origin مثل https://panel.example.com:8443)</label>
<textarea name="allowlist" spellcheck="false"><?= htmlspecialchars($allow) ?></textarea>
<label><input type="checkbox" name="regen_key" value="1"> صدور کلید API تازه</label>
<button type="submit">ذخیره</button>
</form>
</div>
<?php endif; ?>
</div></body></html>
