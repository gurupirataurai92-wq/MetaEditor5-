<?php
declare(strict_types=1);

namespace Haulr;

use RuntimeException;

final class Config
{
    private static ?array $values = null;

    private static function load(): array
    {
        if (self::$values !== null) {
            return self::$values;
        }

        $path = dirname(__DIR__) . '/config.php';
        if (!is_file($path)) {
            throw new RuntimeException(
                'config.php is missing from the project root. It ships with the download — '
                . 'if you deleted it, restore it from the zip.'
            );
        }

        $values = require $path;
        if (!is_array($values)) {
            throw new RuntimeException('config.php must return an array.');
        }

        // Refuse to run on the shipped placeholder key anywhere but locally.
        // A predictable key means anybody can mint a valid session cookie.
        $isLocal = in_array($_SERVER['SERVER_NAME'] ?? 'cli', ['localhost', '127.0.0.1', '::1', 'cli'], true);
        if (!$isLocal && str_starts_with((string) ($values['app_key'] ?? ''), 'change-me')) {
            throw new RuntimeException(
                'Set a real app_key in config.php before serving this to anyone else.'
            );
        }

        self::$values = $values;
        return $values;
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        $values = self::load();
        return $values[$key] ?? $default;
    }

    public static function appKey(): string
    {
        return (string) self::get('app_key');
    }

    public static function isHttps(): bool
    {
        return (bool) self::get('https_only', false);
    }
}
