<?php
/**
 * Database connection for LAKA LAKA CHICKEN (XAMPP / MySQL / MariaDB).
 *
 * Default XAMPP MySQL credentials are user "root" with an empty password.
 * Change these if your XAMPP MySQL is secured differently.
 */

define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'laka_laka_chicken');
define('DB_USER', 'root');
define('DB_PASS', '');       // XAMPP default: empty password
define('DB_PORT', 3306);

// VAT rate used across the POS (15% — ZIMRA standard rate).
define('TAX_RATE', 0.15);

function db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) {
        return $pdo;
    }
    $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', DB_HOST, DB_PORT, DB_NAME);
    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        die(
            '<h2 style="font-family:sans-serif">Database connection failed</h2>' .
            '<p style="font-family:sans-serif">' . htmlspecialchars($e->getMessage()) . '</p>' .
            '<p style="font-family:sans-serif">Make sure MySQL is running in XAMPP and that you have ' .
            'imported <code>sql/laka_laka_chicken.sql</code> via phpMyAdmin.</p>'
        );
    }
    return $pdo;
}

function money(float $n): string
{
    return number_format($n, 2);
}
