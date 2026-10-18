<?php
define('PB_VERSION', trim((string) @file_get_contents(dirname(__DIR__) . '/VERSION')) ?: '0.0.0');
define('PB_ROOT', dirname(__DIR__));
define('PB_STORAGE', PB_ROOT . '/storage');

function pb_config() {
    static $c;
    if ($c === null) {
        $file = PB_ROOT . '/config.php';
        if (!is_file($file)) {
            http_response_code(503);
            header('Content-Type: text/plain; charset=utf-8');
            echo "Polban is not configured.\n";
            exit;
        }
        $c = require $file;
    }
    return $c;
}

function pb_json($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('X-Polban-Version: ' . PB_VERSION);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function pb_log($msg) {
    $dir = PB_STORAGE . '/logs';
    if (!is_dir($dir)) {
        @mkdir($dir, 0750, true);
    }
    @file_put_contents($dir . '/app.log', date('c') . ' ' . $msg . "\n", FILE_APPEND | LOCK_EX);
}

function pb_origin($url) {
    $p = parse_url($url);
    if (empty($p['scheme']) || empty($p['host'])) {
        return '';
    }
    $o = strtolower($p['scheme']) . '://' . strtolower($p['host']);
    if (!empty($p['port'])) {
        $o .= ':' . (int) $p['port'];
    }
    return $o;
}

function pb_allowed($url, array $cfg) {
    $origin = pb_origin($url);
    if ($origin === '') {
        return false;
    }
    foreach ((array) $cfg['allowlist'] as $a) {
        $a = rtrim((string) $a, '/');
        if ($a !== '' && strcasecmp($origin, pb_origin($a)) === 0) {
            return true;
        }
    }
    return false;
}

function pb_proxy(array $cfg, $method, $url, array $headers, $body) {
    if (!pb_allowed($url, $cfg)) {
        return array('ok' => false, 'code' => 403, 'error' => 'upstream not in allowlist', 'body' => '');
    }
    $ch = curl_init($url);
    $h = array();
    foreach ($headers as $k => $v) {
        if ($k === '' || strcasecmp($k, 'Host') === 0 || strcasecmp($k, 'X-Polban-Key') === 0) {
            continue;
        }
        $h[] = $k . ': ' . $v;
    }
    curl_setopt_array($ch, array(
        CURLOPT_CUSTOMREQUEST  => strtoupper($method),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER         => true,
        CURLOPT_HTTPHEADER     => $h,
        CURLOPT_TIMEOUT        => (int) ($cfg['timeout'] ?? 25),
        CURLOPT_SSL_VERIFYPEER => !empty($cfg['verify_ssl']),
        CURLOPT_SSL_VERIFYHOST => !empty($cfg['verify_ssl']) ? 2 : 0,
        CURLOPT_FOLLOWLOCATION => false,
    ));
    if ($body !== null && $body !== '') {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    }
    $raw = curl_exec($ch);
    if ($raw === false) {
        $err = curl_error($ch);
        curl_close($ch);
        return array('ok' => false, 'code' => 0, 'error' => $err, 'body' => '', 'headers' => array());
    }
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $hsz  = (int) curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    curl_close($ch);
    $hdrBlock = substr($raw, 0, $hsz);
    $respBody = substr($raw, $hsz);
    $outH = array();
    foreach (explode("\r\n", $hdrBlock) as $line) {
        if (strpos($line, ':') !== false) {
            list($hk, $hv) = explode(':', $line, 2);
            $outH[trim($hk)] = trim($hv);
        }
    }
    return array(
        'ok'      => $code >= 200 && $code < 500,
        'code'    => $code,
        'error'   => '',
        'body'    => $respBody,
        'headers' => $outH,
    );
}
