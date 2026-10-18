<?php
/**
 * Copy to config.php (install.sh does this).
 * Do not commit config.php.
 */
return array(
    // Public base URL of this Polban install (no trailing slash), e.g. https://bridge.example.com
    'base_url'     => '',
    // Shared secret WordPress sends as X-Polban-Key
    'api_key'      => '',
    // Bcrypt hash of the web admin password (set by installer)
    'admin_pass'   => '',
    // Secret path segment for the web panel, e.g. pb-a1b2c3d4
    'admin_path'   => 'pb-changeme',
    // Allowed upstream panel origin prefixes (scheme://host[:port] only)
    'allowlist'    => array(
        // 'https://panel.example.com:8443',
    ),
    // Request timeout to upstream (seconds)
    'timeout'      => 25,
    // Verify upstream TLS certificates
    'verify_ssl'   => false,
);
