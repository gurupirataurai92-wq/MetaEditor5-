<?php
/**
 * Haulr configuration — this is the only file you normally need to edit.
 *
 * The defaults match a stock XAMPP install (root user, no password), so on a
 * fresh XAMPP you can usually leave this alone.
 */

return [
    // ---- Database -------------------------------------------------------
    'db' => [
        'host'     => '127.0.0.1',
        'port'     => 3306,
        'name'     => 'haulr',
        'user'     => 'root',
        // Stock XAMPP ships MySQL with a blank root password. Set one in
        // phpMyAdmin (User accounts → root → Change password) and put it here
        // before this is reachable by anyone but you.
        'password' => '',
        'charset'  => 'utf8mb4',
    ],

    // ---- Security -------------------------------------------------------

    // Signing key for session tokens and cookies. CHANGE THIS before putting
    // the site anywhere other than your own machine. Generate one with:
    //   php -r "echo bin2hex(random_bytes(32));"
    'app_key' => 'change-me-a1b2c3d4e5f60718293a4b5c6d7e8f90112233445566778899aabbccddeeff',

    // How long a sign-in lasts.
    'session_lifetime_days' => 7,

    // Set true once the site is served over HTTPS. Leave false on plain
    // http://localhost or cookies marked Secure will never be sent back.
    'https_only' => false,

    // Managers can read every job and every customer's contact details, so
    // they carry a second factor. Only turn this off for a local demo.
    'require_manager_2fa' => true,

    // ---- Business -------------------------------------------------------
    'currency' => ['code' => 'ZAR', 'symbol' => 'R'],

    // How far an operator sees jobs by default.
    'dispatch_radius_km' => 25,

    // An on-duty driver whose phone has not reported a position in this long
    // stops appearing on the customer-facing maps.
    'operator_stale_minutes' => 10,
];
