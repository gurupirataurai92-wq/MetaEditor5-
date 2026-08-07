<?php
/**
 * Database connection.
 *
 * One PDO handle per request, throwing exceptions, returning associative
 * arrays, with real prepared statements. Every query in this application goes
 * through here with bound parameters — never string concatenation.
 */

if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) { return $pdo; }

    $dsn = 'mysql:host=' . DB_HOST . ';port=' . DB_PORT . ';dbname=' . DB_NAME . ';charset=utf8mb4';
    try {
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_STRINGIFY_FETCHES  => false,
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        if (SHOW_ERRORS) {
            echo '<h1 style="font:600 20px system-ui;margin:40px">Cannot reach the database</h1>';
            echo '<p style="font:15px system-ui;margin:0 40px;max-width:60em">'
               . htmlspecialchars($e->getMessage(), ENT_QUOTES) . '</p>';
            echo '<ol style="font:15px system-ui;margin:16px 40px;max-width:60em;line-height:1.7">'
               . '<li>Is MySQL started in the XAMPP control panel?</li>'
               . '<li>Has <code>sql/lymond_schema.sql</code> been imported in phpMyAdmin?</li>'
               . '<li>Do the details in <code>includes/config.php</code> match your MySQL setup?</li>'
               . '</ol>';
        } else {
            echo 'The site is temporarily unavailable.';
        }
        exit;
    }
    return $pdo;
}

/** Run a query with bound parameters and return the statement. */
function q(string $sql, array $params = []): PDOStatement
{
    $st = db()->prepare($sql);
    $st->execute($params);
    return $st;
}

/** First row, or null. */
function q_one(string $sql, array $params = []): ?array
{
    $row = q($sql, $params)->fetch();
    return $row === false ? null : $row;
}

/** All rows. */
function q_all(string $sql, array $params = []): array
{
    return q($sql, $params)->fetchAll();
}

/** Single scalar value from the first column. */
function q_val(string $sql, array $params = [], $default = null)
{
    $v = q($sql, $params)->fetchColumn();
    return $v === false ? $default : $v;
}
