<?php
/** PDO connection to the MySQL database (managed via phpMyAdmin in XAMPP). */
require_once __DIR__ . '/config.php';

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }
    $dsn = 'mysql:host=' . DB_HOST . ';port=' . DB_PORT . ';dbname=' . DB_NAME . ';charset=utf8mb4';
    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo '<div style="font-family:system-ui;max-width:640px;margin:60px auto;padding:24px;'
           . 'border:1px solid #eab;border-radius:12px;background:#fff5f5;color:#902">';
        echo '<h2 style="margin:0 0 8px">Cannot connect to the database</h2>';
        echo '<p>Make sure <b>MySQL is started in the XAMPP control panel</b>, then run the '
           . 'one-time setup: <a href="install.php">install.php</a>.</p>';
        echo '<p style="color:#a55;font-size:.9em">' . htmlspecialchars($e->getMessage()) . '</p>';
        echo '</div>';
        exit;
    }
    return $pdo;
}
