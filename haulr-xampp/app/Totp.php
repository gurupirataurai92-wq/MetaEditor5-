<?php
declare(strict_types=1);

namespace Haulr;

/**
 * RFC 6238 time-based one-time passwords.
 *
 * Written against PHP's own hash_hmac so manager accounts can be protected
 * with any standard authenticator app (Google Authenticator, Aegis,
 * 1Password, Microsoft Authenticator) with no extra dependency to install
 * into XAMPP.
 */
final class Totp
{
    public const STEP_SECONDS = 30;
    public const DIGITS = 6;

    /** Accept one step either side to allow for clock drift on the phone. */
    private const DRIFT_STEPS = 1;

    private const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    private static function base32Encode(string $bytes): string
    {
        $bits = 0;
        $value = 0;
        $out = '';
        foreach (str_split($bytes) as $char) {
            $value = ($value << 8) | ord($char);
            $bits += 8;
            while ($bits >= 5) {
                $out .= self::BASE32[($value >> ($bits - 5)) & 31];
                $bits -= 5;
            }
        }
        if ($bits > 0) {
            $out .= self::BASE32[($value << (5 - $bits)) & 31];
        }
        return $out;
    }

    private static function base32Decode(string $input): string
    {
        $clean = strtoupper(preg_replace('/[^A-Z2-7]/i', '', $input) ?? '');
        $bits = 0;
        $value = 0;
        $out = '';
        foreach (str_split($clean) as $char) {
            $index = strpos(self::BASE32, $char);
            if ($index === false) {
                continue;
            }
            $value = ($value << 5) | $index;
            $bits += 5;
            if ($bits >= 8) {
                $out .= chr(($value >> ($bits - 8)) & 0xFF);
                $bits -= 8;
            }
        }
        return $out;
    }

    /** A fresh 160-bit secret, base32-encoded for authenticator apps. */
    public static function generateSecret(): string
    {
        return self::base32Encode(random_bytes(20));
    }

    private static function codeForCounter(string $secretBase32, int $counter): string
    {
        $key = self::base32Decode($secretBase32);
        $binaryCounter = pack('J', $counter); // 64-bit big-endian

        $digest = hash_hmac('sha1', $binaryCounter, $key, true);
        $offset = ord($digest[strlen($digest) - 1]) & 0x0F;

        $binary = ((ord($digest[$offset]) & 0x7F) << 24)
            | ((ord($digest[$offset + 1]) & 0xFF) << 16)
            | ((ord($digest[$offset + 2]) & 0xFF) << 8)
            | (ord($digest[$offset + 3]) & 0xFF);

        return str_pad((string) ($binary % (10 ** self::DIGITS)), self::DIGITS, '0', STR_PAD_LEFT);
    }

    /** The code an authenticator would be showing right now. */
    public static function currentCode(string $secretBase32, ?int $at = null): string
    {
        $at ??= time();
        return self::codeForCounter($secretBase32, intdiv($at, self::STEP_SECONDS));
    }

    /**
     * Verify a submitted code.
     *
     * Returns the matching counter so the caller can store it and refuse a
     * replay of the same code, or null when it does not match.
     */
    public static function verify(
        string $secretBase32,
        string $submitted,
        ?int $lastUsedCounter = null,
        ?int $at = null
    ): ?int {
        $code = preg_replace('/\D/', '', $submitted) ?? '';
        if (strlen($code) !== self::DIGITS) {
            return null;
        }

        $at ??= time();
        $current = intdiv($at, self::STEP_SECONDS);

        for ($drift = -self::DRIFT_STEPS; $drift <= self::DRIFT_STEPS; $drift++) {
            $counter = $current + $drift;
            // A code is single-use: replaying one captured inside its 30s
            // window must fail.
            if ($lastUsedCounter !== null && $counter <= $lastUsedCounter) {
                continue;
            }
            if (hash_equals(self::codeForCounter($secretBase32, $counter), $code)) {
                return $counter;
            }
        }
        return null;
    }

    /** The otpauth:// URI an authenticator app's QR code encodes. */
    public static function provisioningUri(string $secretBase32, string $account, string $issuer = 'Haulr'): string
    {
        $label = rawurlencode($issuer . ':' . $account);
        $params = http_build_query([
            'secret'    => $secretBase32,
            'issuer'    => $issuer,
            'algorithm' => 'SHA1',
            'digits'    => self::DIGITS,
            'period'    => self::STEP_SECONDS,
        ]);
        return "otpauth://totp/$label?$params";
    }

    /**
     * Single-use recovery codes for a lost authenticator. Only their hashes
     * are stored, so reading the database cannot yield a working code.
     */
    public static function generateRecoveryCodes(int $count = 8): array
    {
        $codes = [];
        for ($i = 0; $i < $count; $i++) {
            $raw = strtoupper(bin2hex(random_bytes(5)));
            $codes[] = substr($raw, 0, 5) . '-' . substr($raw, 5);
        }
        return $codes;
    }

    public static function hashRecoveryCode(string $code): string
    {
        return hash('sha256', strtoupper(preg_replace('/\s/', '', $code) ?? ''));
    }
}
