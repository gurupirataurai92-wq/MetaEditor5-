<?php
declare(strict_types=1);

namespace Haulr;

/**
 * Sessions, password handling and role guards.
 *
 * Sessions are server-side rows keyed by an opaque random token. There is no
 * signed self-contained token to forge or replay: authority lives entirely in
 * the `sessions` table, which is what makes instant revocation — sign out
 * everywhere, manager-forced logout, suspension — actually work.
 */
final class Auth
{
    private const BCRYPT_COST = 12;

    private static ?array $user = null;
    private static ?array $session = null;
    private static bool $resolved = false;

    /* ==================================================================
       Passwords
       ================================================================== */

    public static function hashPassword(string $plain): string
    {
        return password_hash($plain, PASSWORD_BCRYPT, ['cost' => self::BCRYPT_COST]);
    }

    public static function verifyPassword(string $plain, ?string $hash): bool
    {
        if ($hash === null || $hash === '') {
            self::burnTime($plain);
            return false;
        }
        return password_verify($plain, $hash);
    }

    /**
     * Spend the same CPU as a real password check, then fail.
     *
     * Without this, "no such account" returns far faster than "wrong
     * password", and the login endpoint becomes a way to discover who has an
     * account here.
     */
    public static function burnTime(string $plain): bool
    {
        static $dummyHash = null;
        $dummyHash ??= password_hash('a-password-that-is-never-valid', PASSWORD_BCRYPT, ['cost' => self::BCRYPT_COST]);
        password_verify($plain, $dummyHash);
        return false;
    }

    /* ==================================================================
       Sessions
       ================================================================== */

    public static function sessionLifetimeSeconds(): int
    {
        return (int) Config::get('session_lifetime_days', 7) * 86400;
    }

    /**
     * Create a session and return the raw token for the cookie.
     * Only the token's hash is stored.
     */
    public static function createSession(array $user): array
    {
        $token     = Security::randomToken(32);
        $sessionId = self::uuid4();
        $csrfToken = Security::randomToken(32);
        $lifetime  = self::sessionLifetimeSeconds();

        Database::run(
            'INSERT INTO sessions (id, user_id, token_hash, csrf_token, ip, user_agent, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
            [
                $sessionId,
                (int) $user['id'],
                Security::hashToken($token),
                $csrfToken,
                Security::clientIp(),
                Security::userAgent(),
                $lifetime,
            ]
        );

        return [
            'token'     => $token,
            'csrfToken' => $csrfToken,
            'sessionId' => $sessionId,
            'lifetime'  => $lifetime,
        ];
    }

    public static function revokeSession(string $sessionId, ?int $revokedBy = null): void
    {
        Database::run(
            'UPDATE sessions SET revoked_at = NOW(), revoked_by = ?
              WHERE id = ? AND revoked_at IS NULL',
            [$revokedBy, $sessionId]
        );
    }

    /** Revoke every live session for a user. Returns how many were killed. */
    public static function revokeAllSessions(int $userId, ?int $revokedBy = null, ?string $exceptSessionId = null): int
    {
        if ($exceptSessionId !== null) {
            return Database::affected(
                'UPDATE sessions SET revoked_at = NOW(), revoked_by = ?
                  WHERE user_id = ? AND revoked_at IS NULL AND id <> ?',
                [$revokedBy, $userId, $exceptSessionId]
            );
        }
        return Database::affected(
            'UPDATE sessions SET revoked_at = NOW(), revoked_by = ?
              WHERE user_id = ? AND revoked_at IS NULL',
            [$revokedBy, $userId]
        );
    }

    public static function listSessions(int $userId): array
    {
        return Database::all(
            'SELECT id, ip, user_agent, created_at, last_seen_at, expires_at, revoked_at
               FROM sessions WHERE user_id = ?
              ORDER BY created_at DESC LIMIT 50',
            [$userId]
        );
    }

    /* ==================================================================
       Resolving the current caller
       ================================================================== */

    /**
     * Work out who is calling, from the session cookie.
     *
     * The user row is re-read on every request, so a suspension or a revoked
     * session takes effect immediately rather than whenever a token expires.
     */
    public static function resolve(): void
    {
        if (self::$resolved) {
            return;
        }
        self::$resolved = true;

        $token = $_COOKIE[Security::SESSION_COOKIE] ?? null;
        if (!is_string($token) || $token === '') {
            return;
        }

        $session = Database::first(
            'SELECT * FROM sessions
              WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > NOW()',
            [Security::hashToken($token)]
        );
        if ($session === null) {
            return;
        }

        $user = Database::first(
            'SELECT id, role, full_name, email, phone, rating_sum, rating_count,
                    is_suspended, suspended_reason, totp_enabled, must_change_password, created_at
               FROM users WHERE id = ?',
            [(int) $session['user_id']]
        );
        if ($user === null || (int) $user['is_suspended'] === 1) {
            return;
        }

        self::$user = $user;
        self::$session = $session;

        // Cheap liveness tracking for the "your active sessions" screen,
        // written at most once a minute so a chatty client cannot hammer it.
        if (strtotime((string) $session['last_seen_at']) < time() - 60) {
            Database::run('UPDATE sessions SET last_seen_at = NOW() WHERE id = ?', [$session['id']]);
        }
    }

    public static function user(): ?array
    {
        self::resolve();
        return self::$user;
    }

    public static function session(): ?array
    {
        self::resolve();
        return self::$session;
    }

    public static function id(): ?int
    {
        $user = self::user();
        return $user === null ? null : (int) $user['id'];
    }

    public static function role(): ?string
    {
        $user = self::user();
        return $user === null ? null : (string) $user['role'];
    }

    public static function isManager(): bool
    {
        return self::role() === 'manager';
    }

    public static function forget(): void
    {
        self::$user = null;
        self::$session = null;
    }

    /* ==================================================================
       Guards
       ================================================================== */

    public static function requireAuth(): array
    {
        $user = self::user();
        if ($user === null) {
            Response::error('Sign in to continue.', 401);
        }
        return $user;
    }

    public static function requireRole(string ...$roles): array
    {
        $user = self::requireAuth();
        if (!in_array((string) $user['role'], $roles, true)) {
            Response::error('Your account cannot perform this action.', 403);
        }
        return $user;
    }

    /**
     * A manager who has not enrolled a second factor holds a deliberately
     * crippled session: it exists only so they can complete enrolment.
     */
    public static function mustEnrolTwoFactor(?array $user = null): bool
    {
        $user ??= self::user();
        return $user !== null
            && $user['role'] === 'manager'
            && (int) $user['totp_enabled'] === 0
            && (bool) Config::get('require_manager_2fa', true);
    }

    /** Blocks manager work until the second factor is in place. */
    public static function requireEnrolledTwoFactor(): void
    {
        if (self::mustEnrolTwoFactor()) {
            Response::error(
                'Set up two-factor authentication before using the manager console. '
                . 'It is mandatory for manager accounts.',
                403,
                ['code' => 'ENROL_2FA']
            );
        }
    }

    /* ==================================================================
       CSRF
       ================================================================== */

    /**
     * Reject a state-changing request that does not echo the session's CSRF
     * token in a header.
     *
     * SameSite=Strict already blocks the classic cross-site form post; this is
     * the belt to that braces and covers browsers or proxies that mishandle it.
     */
    public static function checkCsrf(string $method): void
    {
        if (in_array($method, ['GET', 'HEAD', 'OPTIONS'], true)) {
            return;
        }
        $session = self::session();
        if ($session === null) {
            return; // unauthenticated requests have no session to protect
        }

        $submitted = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '';
        if (!is_string($submitted) || !Security::safeEquals($submitted, (string) $session['csrf_token'])) {
            Response::error(
                'Security check failed. Refresh the page and try again.',
                403,
                ['code' => 'CSRF']
            );
        }
    }

    /* ==================================================================
       Presentation
       ================================================================== */

    /** Public shape of a user — never leaks hashes, secrets or lock state. */
    public static function publicUser(?array $user): ?array
    {
        if ($user === null) {
            return null;
        }
        $count = (int) ($user['rating_count'] ?? 0);
        return [
            'id'                 => (int) $user['id'],
            'role'               => (string) $user['role'],
            'fullName'           => (string) $user['full_name'],
            'email'              => (string) $user['email'],
            'phone'              => (string) $user['phone'],
            'rating'             => $count > 0 ? round(((float) $user['rating_sum']) / $count, 2) : null,
            'ratingCount'        => $count,
            'twoFactorEnabled'   => (bool) ($user['totp_enabled'] ?? false),
            'mustEnrolTwoFactor' => self::mustEnrolTwoFactor($user),
            'mustChangePassword' => (bool) ($user['must_change_password'] ?? false),
            'createdAt'          => $user['created_at'] ?? null,
        ];
    }

    /** Where each role's dashboard lives. The client follows this, not a guess. */
    public static function homePathFor(string $role): string
    {
        return match ($role) {
            'operator' => 'operator.html',
            'manager'  => 'manager.html',
            default    => 'customer.html',
        };
    }

    private static function uuid4(): string
    {
        $data = random_bytes(16);
        $data[6] = chr((ord($data[6]) & 0x0F) | 0x40);
        $data[8] = chr((ord($data[8]) & 0x3F) | 0x80);
        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
    }
}
