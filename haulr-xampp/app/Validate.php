<?php
declare(strict_types=1);

namespace Haulr;

/** Thrown by the helpers below; the router turns it into a 400. */
final class ValidationError extends \RuntimeException
{
}

final class Validate
{
    public static function str(
        mixed $value,
        string $field,
        int $min = 1,
        int $max = 500,
        bool $required = true
    ): ?string {
        if ($value === null || $value === '' || (is_string($value) && trim($value) === '')) {
            if ($required) {
                throw new ValidationError("$field is required.");
            }
            return null;
        }
        if (!is_scalar($value)) {
            throw new ValidationError("$field must be text.");
        }

        $s = trim((string) $value);
        if (mb_strlen($s) < $min) {
            throw new ValidationError("$field must be at least $min characters.");
        }
        if (mb_strlen($s) > $max) {
            throw new ValidationError("$field must be at most $max characters.");
        }
        return $s;
    }

    public static function num(
        mixed $value,
        string $field,
        float $min = -INF,
        float $max = INF,
        bool $required = true,
        bool $integer = false
    ): int|float|null {
        if ($value === null || $value === '') {
            if ($required) {
                throw new ValidationError("$field is required.");
            }
            return null;
        }
        if (!is_numeric($value)) {
            throw new ValidationError("$field must be a number.");
        }

        $n = $value + 0;
        if ($integer && floor((float) $n) != $n) {
            throw new ValidationError("$field must be a whole number.");
        }
        if ($n < $min) {
            throw new ValidationError("$field must be at least $min.");
        }
        if ($n > $max) {
            throw new ValidationError("$field must be at most $max.");
        }
        return $integer ? (int) $n : (float) $n;
    }

    public static function bool(mixed $value): bool
    {
        return $value === true || $value === 1 || $value === '1' || $value === 'true';
    }

    /** @param string[] $allowed */
    public static function oneOf(mixed $value, string $field, array $allowed): string
    {
        $s = is_scalar($value) ? trim((string) $value) : '';
        if (!in_array($s, $allowed, true)) {
            throw new ValidationError("$field must be one of: " . implode(', ', $allowed) . '.');
        }
        return $s;
    }

    public static function latitude(mixed $value, string $field = 'Latitude'): float
    {
        return (float) self::num($value, $field, -90, 90);
    }

    public static function longitude(mixed $value, string $field = 'Longitude'): float
    {
        return (float) self::num($value, $field, -180, 180);
    }

    public static function email(mixed $value): string
    {
        $s = mb_strtolower(self::str($value, 'Email', 3, 254));
        if (!filter_var($s, FILTER_VALIDATE_EMAIL)) {
            throw new ValidationError('Enter a valid email address.');
        }
        return $s;
    }

    /**
     * Deliberately permissive — international numbering plans vary wildly and
     * an over-strict rule turns away real customers.
     */
    public static function phone(mixed $value): string
    {
        $s = self::str($value, 'Phone number', 7, 24);
        if (!preg_match('/^\+?[0-9][0-9\s\-().]{6,23}$/', $s)) {
            throw new ValidationError('Enter a valid phone number.');
        }
        return $s;
    }

    /** A MySQL DATETIME string, or null. */
    public static function datetime(mixed $value, string $field, bool $required = false): ?string
    {
        if ($value === null || $value === '') {
            if ($required) {
                throw new ValidationError("$field is required.");
            }
            return null;
        }
        $ts = strtotime((string) $value);
        if ($ts === false) {
            throw new ValidationError("$field is not a valid date.");
        }
        return date('Y-m-d H:i:s', $ts);
    }
}
