<?php
require dirname(__DIR__) . '/lib/bootstrap.php';

$cfg = pb_config();
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$uri = rawurldecode((string) $uri);

// Web admin under secret path
$admin = '/' . trim((string) $cfg['admin_path'], '/');
if ($admin !== '/' && (strpos($uri, $admin) === 0)) {
    require dirname(__DIR__) . '/app/admin.php';
    exit;
}

if ($uri === '/' || $uri === '') {
    pb_json(array('ok' => true, 'service' => 'polban', 'version' => PB_VERSION));
}

if ($uri === '/v1/health') {
    pb_json(array(
        'ok'        => true,
        'version'   => PB_VERSION,
        'allowlist' => count((array) $cfg['allowlist']),
    ));
}

// Add origin to allowlist (API key protected)
if ($uri === '/v1/allowlist' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $key = isset($_SERVER['HTTP_X_POLBAN_KEY']) ? (string) $_SERVER['HTTP_X_POLBAN_KEY'] : '';
    if ($key === '' || !hash_equals((string) $cfg['api_key'], $key)) {
        pb_json(array('ok' => false, 'error' => 'unauthorized'), 401);
    }
    $raw = file_get_contents('php://input');
    $in = json_decode($raw, true);
    if (!is_array($in) || empty($in['origin'])) {
        pb_json(array('ok' => false, 'error' => 'origin required'), 400);
    }
    $origin = pb_origin((string) $in['origin']);
    if ($origin === '') {
        pb_json(array('ok' => false, 'error' => 'invalid origin'), 400);
    }
    $list = (array) $cfg['allowlist'];
    if (!in_array($origin, $list, true)) {
        $list[] = $origin;
        $cfg['allowlist'] = array_values(array_unique($list));
        $export = "<?php\nreturn " . var_export($cfg, true) . ";\n";
        $cfg_file = PB_ROOT . '/config.php';
        if (@file_put_contents($cfg_file, $export, LOCK_EX) === false) {
            pb_log('allowlist add FAILED: config.php not writable');
            pb_json(array('ok' => false, 'error' => 'config not writable'), 500);
        }
        if (function_exists('opcache_invalidate')) {
            @opcache_invalidate($cfg_file, true);
        }
        pb_log('allowlist added: ' . $origin);
    }
    pb_json(array('ok' => true, 'origin' => $origin, 'allowlist' => $cfg['allowlist']));
}

if ($uri === '/v1/proxy' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $key = isset($_SERVER['HTTP_X_POLBAN_KEY']) ? (string) $_SERVER['HTTP_X_POLBAN_KEY'] : '';
    if ($key === '' || !hash_equals((string) $cfg['api_key'], $key)) {
        pb_json(array('ok' => false, 'error' => 'unauthorized'), 401);
    }
    $raw = file_get_contents('php://input');
    $in = json_decode($raw, true);
    if (!is_array($in) || empty($in['url']) || empty($in['method'])) {
        pb_json(array('ok' => false, 'error' => 'url and method required'), 400);
    }
    $headers = isset($in['headers']) && is_array($in['headers']) ? $in['headers'] : array();
    $body = array_key_exists('body', $in) ? $in['body'] : null;
    $res = pb_proxy($cfg, (string) $in['method'], (string) $in['url'], $headers, $body);
    pb_log('proxy ' . strtoupper($in['method']) . ' ' . pb_origin($in['url']) . ' -> ' . $res['code'] . ($res['error'] ? ' ' . $res['error'] : ''));
    pb_json(array(
        'ok'      => $res['error'] === '',
        'code'    => $res['code'],
        'error'   => $res['error'],
        'headers' => $res['headers'],
        'body'    => $res['body'],
    ), $res['error'] !== '' ? 502 : 200);
}

pb_json(array('ok' => false, 'error' => 'not found'), 404);
