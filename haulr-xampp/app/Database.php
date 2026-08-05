<?php
declare(strict_types=1);

namespace Haulr;

use PDO;
use PDOException;
use RuntimeException;

/**
 * Thin PDO wrapper.
 *
 * Every query in this application goes through these helpers with bound
 * parameters — no SQL is ever built by concatenating user input.
 */
final class Database
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $cfg = Config::get('db');
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            $cfg['host'],
            $cfg['port'],
            $cfg['name'],
            $cfg['charset']
        );

        try {
            self::$pdo = new PDO($dsn, $cfg['user'], $cfg['password'], [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                // Real prepared statements, not driver-side emulation: the
                // value never gets interpolated into the SQL string at all.
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_STRINGIFY_FETCHES  => false,
            ]);
        } catch (PDOException $e) {
            throw new RuntimeException(
                'Cannot connect to MySQL. Is it started in the XAMPP control panel, and '
                . 'do the credentials in config.php match? (' . $e->getMessage() . ')'
            );
        }

        return self::$pdo;
    }

    /** Run a statement; returns the PDOStatement. */
    public static function run(string $sql, array $params = []): \PDOStatement
    {
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    /** First matching row, or null. */
    public static function first(string $sql, array $params = []): ?array
    {
        $row = self::run($sql, $params)->fetch();
        return $row === false ? null : $row;
    }

    /** All matching rows. */
    public static function all(string $sql, array $params = []): array
    {
        return self::run($sql, $params)->fetchAll();
    }

    /** A single scalar from the first column of the first row. */
    public static function value(string $sql, array $params = [], mixed $default = null): mixed
    {
        $row = self::run($sql, $params)->fetch(PDO::FETCH_NUM);
        return $row === false ? $default : $row[0];
    }

    public static function insert(string $sql, array $params = []): int
    {
        self::run($sql, $params);
        return (int) self::pdo()->lastInsertId();
    }

    /** Rows affected by an UPDATE/DELETE. */
    public static function affected(string $sql, array $params = []): int
    {
        return self::run($sql, $params)->rowCount();
    }

    /** Run $fn inside a transaction, rolling back if it throws. */
    public static function transaction(callable $fn): mixed
    {
        $pdo = self::pdo();
        $pdo->beginTransaction();
        try {
            $result = $fn();
            $pdo->commit();
            return $result;
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    }

    /** Has the schema been imported yet? */
    public static function isInstalled(): bool
    {
        try {
            self::value('SELECT 1 FROM users LIMIT 1');
            return true;
        } catch (\Throwable) {
            return false;
        }
    }
}
