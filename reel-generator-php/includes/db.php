<?php
/**
 * Database bootstrap: a single shared PDO connection with optional
 * self-install of the schema (so the app "just works" on a fresh XAMPP).
 */

declare(strict_types=1);

function config(): array
{
    static $config = null;
    if ($config === null) {
        $config = require __DIR__ . '/../config/config.php';
    }
    return $config;
}

/**
 * Returns a live PDO connection to the app database, creating the database
 * and tables on first use when app.auto_install is enabled.
 *
 * @throws RuntimeException if MySQL is unreachable (e.g. XAMPP not started).
 */
function db(): PDO
{
    static $pdo = null;
    if ($pdo instanceof PDO) {
        return $pdo;
    }

    $c = config()['db'];
    $opts = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ];

    $autoInstall = (bool) (config()['app']['auto_install'] ?? true);

    if ($autoInstall) {
        // Connect to the server (no db) so we can create it if missing.
        $serverDsn = "mysql:host={$c['host']};port={$c['port']};charset={$c['charset']}";
        try {
            $server = new PDO($serverDsn, $c['user'], $c['pass'], $opts);
        } catch (PDOException $e) {
            throw new RuntimeException(
                'Cannot reach MySQL — is XAMPP\'s MySQL module started? (' . $e->getMessage() . ')'
            );
        }
        $server->exec(
            "CREATE DATABASE IF NOT EXISTS `{$c['name']}` "
            . 'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
        );
    }

    $dsn = "mysql:host={$c['host']};port={$c['port']};dbname={$c['name']};charset={$c['charset']}";
    try {
        $pdo = new PDO($dsn, $c['user'], $c['pass'], $opts);
    } catch (PDOException $e) {
        throw new RuntimeException(
            'Connected to MySQL but could not open database "' . $c['name'] . '". '
            . 'Import sql/schema.sql, or set app.auto_install = true. (' . $e->getMessage() . ')'
        );
    }

    if ($autoInstall) {
        run_migrations($pdo);
    }

    return $pdo;
}

/**
 * Applies sql/schema.sql (minus the CREATE DATABASE / USE lines, which the
 * bootstrap already handled). All statements are IF NOT EXISTS, so this is
 * idempotent and cheap to run each request on a dev box.
 */
function run_migrations(PDO $pdo): void
{
    $sql = file_get_contents(__DIR__ . '/../sql/schema.sql');
    if ($sql === false) {
        throw new RuntimeException('Could not read sql/schema.sql for auto-install.');
    }

    foreach (array_filter(array_map('trim', explode(';', $sql))) as $stmt) {
        if ($stmt === '') {
            continue;
        }
        // Skip DB-level statements — we are already connected to the db.
        if (preg_match('/^\s*(CREATE\s+DATABASE|USE)\b/i', $stmt)) {
            continue;
        }
        // Skip pure comment blocks.
        $withoutComments = preg_replace('/^\s*(--[^\n]*\n?)+/', '', $stmt);
        if (trim((string) $withoutComments) === '') {
            continue;
        }
        $pdo->exec($stmt);
    }
}
