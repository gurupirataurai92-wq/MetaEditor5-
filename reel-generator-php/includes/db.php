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

    upgrade_schema($pdo);
    seed_operators($pdo);
}

/**
 * Seeds a default operator on a fresh install so someone can sign in to the
 * console. Credentials are intentionally well-known — change them immediately
 * from the Operators page.
 */
function seed_operators(PDO $pdo): void
{
    $count = (int) $pdo->query('SELECT COUNT(*) FROM operators')->fetchColumn();
    if ($count === 0) {
        $stmt = $pdo->prepare(
            'INSERT INTO operators (username, password_hash, role) VALUES (:u, :p, :r)'
        );
        $stmt->execute([
            ':u' => 'admin',
            ':p' => password_hash('admin123', PASSWORD_DEFAULT),
            ':r' => 'admin',
        ]);
    }
}

/**
 * Additive upgrades for databases created before newer columns existed.
 * Each change is guarded by an information_schema check, so it works on both
 * fresh and existing installs and on both MySQL and MariaDB.
 */
function upgrade_schema(PDO $pdo): void
{
    $columns = [
        "ADD COLUMN `render_style` ENUM('realistic','cartoon') NOT NULL DEFAULT 'cartoon' AFTER `duration_sec`",
        "ADD COLUMN `length_mode` ENUM('short','long') NOT NULL DEFAULT 'short' AFTER `render_style`",
        "ADD COLUMN `source` ENUM('generated','uploaded') NOT NULL DEFAULT 'generated' AFTER `length_mode`",
        "ADD COLUMN `provider` VARCHAR(64) NULL AFTER `source`",
        "ADD COLUMN `video_path` VARCHAR(255) NULL AFTER `provider`",
        "ADD COLUMN `external_job_id` VARCHAR(191) NULL AFTER `video_path`",
    ];
    $map = [
        'render_style'   => $columns[0],
        'length_mode'    => $columns[1],
        'source'         => $columns[2],
        'provider'       => $columns[3],
        'video_path'     => $columns[4],
        'external_job_id'=> $columns[5],
    ];
    foreach ($map as $col => $ddl) {
        if (!column_exists($pdo, 'reels', $col)) {
            $pdo->exec("ALTER TABLE `reels` {$ddl}");
        }
    }

    // scenes.speaker for per-character voices.
    if (!column_exists($pdo, 'scenes', 'speaker')) {
        $pdo->exec("ALTER TABLE `scenes` ADD COLUMN `speaker` VARCHAR(64) NOT NULL DEFAULT 'Narrator' AFTER `scene_index`");
    }

    // Widen the status enum to include 'rendering' if an older install predates it.
    $stmt = $pdo->query(
        "SELECT COLUMN_TYPE FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'reels' AND COLUMN_NAME = 'status'"
    );
    $type = (string) ($stmt->fetchColumn() ?: '');
    if ($type !== '' && stripos($type, "'rendering'") === false) {
        $pdo->exec(
            "ALTER TABLE `reels` MODIFY `status`
             ENUM('queued','scripting','voicing','sourcing_visuals','captioning','assembling','rendering','done','failed')
             NOT NULL DEFAULT 'queued'"
        );
    }
}

/** Whether a column exists on a table in the current database. */
function column_exists(PDO $pdo, string $table, string $column): bool
{
    $stmt = $pdo->prepare(
        'SELECT 1 FROM information_schema.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :t AND COLUMN_NAME = :c
          LIMIT 1'
    );
    $stmt->execute([':t' => $table, ':c' => $column]);
    return $stmt->fetchColumn() !== false;
}
