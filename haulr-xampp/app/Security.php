<?php
declare(strict_types=1);

namespace Haulr;

/**
 * Cookies, CSRF, rate limiting and password policy.
 */
final class Security
{
    public const SESSION_COOKIE = 'haulr_session';
    public const CSRF_COOKIE    = 'haulr_csrf';

    public const MIN_PASSWORD_LENGTH = 12;

    /* ==================================================================
       Cookies
       ================================================================== */

    private static function cookieOptions(int $maxAgeSeconds, bool $httpOnly): array
    {
        return [
            'expires'  => $maxAgeSeconds > 0 ? time() + $maxAgeSeconds : time() - 3600,
            'path'     => self::basePath(),
            // `Secure` is meaningless over plain http and would stop the cookie
            // coming back at all on http://localhost, so it follows config.
            'secure'   => Config::isHttps(),
            'httponly' => $httpOnly,
            'samesite' => 'Strict',
        ];
    }

    /**
     * The folder the app is served from, e.g. "/haulr/". Scoping cookies to it
     * keeps them off other XAMPP projects sharing localhost.
     */
    public static function basePath(): string
    {
        $script = str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? '/')));
        // .../haulr/api  ->  /haulr
        if (str_ends_with($script, '/api')) {
            $script = substr($script, 0, -4);
        }
        $script = rtrim($script, '/');
        return $script === '' ? '/' : $script . '/';
    }

    /**
     * The session token goes in an httpOnly cookie. This is the single most
     * valuable hardening step here: script on the page cannot read it, so an
     * XSS bug cannot be turned into a stolen, portable session.
     */
    public static function setSessionCookie(string $token, int $lifetimeSeconds): void
    {
        setcookie(self::SESSION_COOKIE, $token, self::cookieOptions($lifetimeSeconds, true));
    }

    /**
     * The CSRF token is deliberately readable by our own scripts — the page
     * has to echo it back in a header. On its own it proves nothing except
     * that the caller can read a same-origin cookie, which is the point.
     */
    public static function setCsrfCookie(string $token, int $lifetimeSeconds): void
    {
        setcookie(self::CSRF_COOKIE, $token, self::cookieOptions($lifetimeSeconds, false));
    }

    public static function clearAuthCookies(): void
    {
        setcookie(self::SESSION_COOKIE, '', self::cookieOptions(-1, true));
        setcookie(self::CSRF_COOKIE, '', self::cookieOptions(-1, false));
    }

    /* ==================================================================
       Tokens and comparison
       ================================================================== */

    public static function randomToken(int $bytes = 32): string
    {
        return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '=');
    }

    public static function hashToken(string $token): string
    {
        // Session tokens are already high-entropy random values, so a fast
        // hash is right here — it exists to make the stored copy useless,
        // not to slow down guessing.
        return hash('sha256', $token);
    }

    /** Compare without leaking the contents through timing. */
    public static function safeEquals(string $a, string $b): bool
    {
        return hash_equals(hash('sha256', $a), hash('sha256', $b));
    }

    /* ==================================================================
       Client identity
       ================================================================== */

    /**
     * The caller's address.
     *
     * X-Forwarded-For is deliberately ignored: on a stock XAMPP box nothing
     * sets it, so anything arriving in that header is a client trying to
     * rotate identity and dodge rate limiting.
     */
    public static function clientIp(): string
    {
        return (string) ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
    }

    public static function userAgent(): string
    {
        return substr((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 300);
    }

    /* ==================================================================
       Rate limiting
       ================================================================== */

    /**
     * Sliding-window limiter backed by MySQL.
     *
     * Each PHP request is its own process, so an in-memory counter would reset
     * constantly — the shared table is what makes this actually hold.
     *
     * Returns true when the request is allowed.
     */
    public static function rateLimit(string $bucket, string $key, int $max, int $windowSeconds): bool
    {
        $identity = $bucket . ':' . $key;

        // Reuse login_attempts for auth buckets so the security dashboard sees
        // the same data; everything else gets a generic row.
        $count = (int) Database::value(
            'SELECT COUNT(*) FROM login_attempts
              WHERE ip = ? AND email = ? AND created_at > (NOW() - INTERVAL ? SECOND)',
            [self::clientIp(), $identity, $windowSeconds],
            0
        );

        if ($count >= $max) {
            return false;
        }

        Database::run(
            'INSERT INTO login_attempts (email, ip, succeeded) VALUES (?, ?, 1)',
            [$identity, self::clientIp()]
        );
        return true;
    }

    /** Housekeeping so the tables do not grow without bound. */
    public static function pruneOldRecords(): void
    {
        // Roughly one request in fifty does the tidying, which is enough on a
        // single-server install and costs nothing on the other forty-nine.
        if (random_int(1, 50) !== 1) {
            return;
        }
        Database::run('DELETE FROM login_attempts WHERE created_at < (NOW() - INTERVAL 7 DAY)');
        Database::run('DELETE FROM event_queue     WHERE created_at < (NOW() - INTERVAL 1 DAY)');
        Database::run('DELETE FROM sessions        WHERE expires_at < (NOW() - INTERVAL 30 DAY)');
    }

    /* ==================================================================
       Password policy
       ================================================================== */

    /** The passwords that top real breach corpora. */
    private const COMMON_PASSWORDS = [
        'password', 'password1', 'password123', 'passw0rd', '12345678', '123456789',
        '1234567890', 'qwerty123', 'qwertyuiop', 'letmein1', 'welcome1', 'welcome123',
        'admin123', 'administrator', 'iloveyou1', 'sunshine1', 'princess1', 'football1',
        'monkey123', 'abc12345', 'trustno1', 'dragon123', 'baseball1', 'superman1',
        'michael1', 'shadow123', 'master123', 'jennifer1', 'jordan23', 'harley123',
        'changeme', 'changeme1', 'secret123', 'whatever1', 'starwars1', 'computer1',
        'zaq12wsx', '1qaz2wsx', 'qazwsxedc', 'asdfghjkl', 'zxcvbnm1', 'p@ssword',
        'p@ssw0rd', 'haulr1234',
    ];

    /** Returns the list of problems with a password; empty means acceptable. */
    public static function passwordProblems(?string $password, string $email = '', string $fullName = ''): array
    {
        $value = (string) $password;
        $problems = [];

        if (mb_strlen($value) < self::MIN_PASSWORD_LENGTH) {
            $problems[] = 'be at least ' . self::MIN_PASSWORD_LENGTH . ' characters';
        }
        if (mb_strlen($value) > 200) {
            $problems[] = 'be no longer than 200 characters';
        }

        $classes = 0;
        foreach (['/[a-z]/', '/[A-Z]/', '/[0-9]/', '/[^A-Za-z0-9]/'] as $pattern) {
            if (preg_match($pattern, $value)) {
                $classes++;
            }
        }
        if ($classes < 3) {
            $problems[] = 'mix at least three of: lowercase, uppercase, numbers, symbols';
        }

        $lower = mb_strtolower($value);
        if (in_array($lower, self::COMMON_PASSWORDS, true)) {
            $problems[] = 'not be a commonly used password';
        }
        if ($value !== '' && preg_match('/^(.)\1+$/u', $value)) {
            $problems[] = 'not be a single repeated character';
        }
        if (preg_match('/^(0123456789|1234567890|abcdefghijkl|qwertyuiopas)/', $lower)) {
            $problems[] = 'not be a keyboard or counting sequence';
        }

        $localPart = mb_strtolower(explode('@', $email)[0] ?? '');
        if ($localPart !== '' && mb_strlen($localPart) >= 4 && str_contains($lower, $localPart)) {
            $problems[] = 'not contain your email address';
        }
        foreach (preg_split('/\s+/', mb_strtolower($fullName)) ?: [] as $part) {
            if (mb_strlen($part) >= 4 && str_contains($lower, $part)) {
                $problems[] = 'not contain your name';
                break;
            }
        }

        return array_values(array_unique($problems));
    }

    public static function describePasswordPolicy(): string
    {
        return 'At least ' . self::MIN_PASSWORD_LENGTH . ' characters, mixing at least three of '
            . 'lowercase, uppercase, numbers and symbols. It must not be a common password or '
            . 'contain your name or email.';
    }

    /* ==================================================================
       Response headers
       ================================================================== */

    public static function sendSecurityHeaders(): void
    {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: strict-origin-when-cross-origin');
        header('Permissions-Policy: geolocation=(self), camera=(), microphone=(), payment=()');
        header('Cross-Origin-Opener-Policy: same-origin');
        header('Cross-Origin-Resource-Policy: same-origin');
        header('X-DNS-Prefetch-Control: off');
        // No shared cache may ever hold an authenticated API response.
        header('Cache-Control: no-store, no-cache, must-revalidate, private');
        header('Pragma: no-cache');

        if (Config::isHttps()) {
            header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
        }
        // PHP advertises its version by default; that only helps an attacker
        // match a known CVE to this host.
        header_remove('X-Powered-By');
    }
}
