<?php
/**
 * Database connection (PDO) for XAMPP / MySQL (MariaDB).
 * Default XAMPP credentials: user "root", empty password, host 127.0.0.1.
 * Change these if your XAMPP MySQL is configured differently.
 */
$DB_HOST = '127.0.0.1';
$DB_PORT = '3306';
$DB_NAME = 'hivebet';
$DB_USER = 'root';
$DB_PASS = '';

try {
    $pdo = new PDO(
        "mysql:host=$DB_HOST;port=$DB_PORT;dbname=$DB_NAME;charset=utf8mb4",
        $DB_USER,
        $DB_PASS,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
} catch (PDOException $e) {
    if (PHP_SAPI === 'cli') {
        fwrite(STDERR, "Database connection failed: " . $e->getMessage() . "\n"
            . "Start MySQL (XAMPP) and import sql/hivebet.sql via phpMyAdmin.\n");
        exit(1);
    }
    http_response_code(500);
    die(
        '<div style="font-family:system-ui;max-width:640px;margin:60px auto;padding:24px;'
        . 'background:#1a1206;color:#ffd75e;border:1px solid #6b4e00;border-radius:12px">'
        . '<h2>🐝 Database connection failed</h2>'
        . '<p>' . htmlspecialchars($e->getMessage()) . '</p>'
        . '<ol><li>Open the <b>XAMPP Control Panel</b> and Start <b>Apache</b> + <b>MySQL</b>.</li>'
        . '<li>Go to <a href="http://localhost/phpmyadmin" style="color:#ffd75e">phpMyAdmin</a> → '
        . '<b>Import</b> → choose <code>sql/hivebet.sql</code> → Go.</li>'
        . '<li>Reload this page.</li></ol></div>'
    );
}
