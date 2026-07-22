<?php
/* ============================================================
   Database connection (PDO).

   Defaults are the standard XAMPP MySQL settings:
     host = 127.0.0.1, user = root, password = "" (empty),
     database = godmode_consultant

   Edit the four constants below if your MySQL is different.
   (Advanced: the DB_DSN / DB_USER / DB_PASS environment
    variables override these, which is what the test suite uses.)
   ============================================================ */

define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'godmode_consultant');
define('DB_USER', 'root');
define('DB_PASS', '');

function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $envDsn = getenv('DB_DSN');
    if ($envDsn) {
        $dsn  = $envDsn;
        $user = getenv('DB_USER') ?: null;
        $pass = getenv('DB_PASS') ?: null;
    } else {
        $dsn  = 'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4';
        $user = DB_USER;
        $pass = DB_PASS;
    }

    try {
        $pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
        if (strncmp($dsn, 'sqlite', 6) === 0) {
            $pdo->exec('PRAGMA foreign_keys = ON');
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo '<div style="font-family:system-ui;max-width:640px;margin:60px auto;padding:24px;'
           . 'background:#161f2a;color:#dbe4ee;border:1px solid #e05a4e;border-radius:12px">'
           . '<h2 style="color:#e05a4e">Cannot connect to the database</h2>'
           . '<p>' . htmlspecialchars($e->getMessage()) . '</p>'
           . '<p style="color:#8496a9">Start MySQL in the XAMPP control panel, then import '
           . '<code>sql/schema.sql</code> through phpMyAdmin (creates the '
           . '<code>godmode_consultant</code> database). Check the credentials in '
           . '<code>config/db.php</code> if you changed them.</p></div>';
        exit;
    }
    return $pdo;
}
