<?php
declare(strict_types=1);

namespace Haulr\Controllers;

use Haulr\{Audit, Auth, Config, Database, Domain, Response, Security, Serialize, Totp, Validate};

final class AuthController
{
    private const FAILURE_WINDOW_MINUTES = 15;
    private const LOCK_THRESHOLD = 5;

    /* ==================================================================
       Registration
       ================================================================== */

    /**
     * POST api/auth/register
     *
     * Self-service registration creates customers and drivers only. Manager
     * accounts are never obtainable this way — they come from the
     * create-manager script, or from an existing manager inside the console.
     * Letting a stranger self-assign the role that can read every job in the
     * system would be the single worst hole in the product.
     */
    public function register(array $body): never
    {
        if (!Security::rateLimit('register', Security::clientIp(), 8, 3600)) {
            Response::error('Too many accounts created from here. Try again later.', 429);
        }

        $role      = Validate::oneOf($body['role'] ?? null, 'Account type', ['customer', 'operator']);
        $fullName  = Validate::str($body['fullName'] ?? null, 'Full name', 2, 120);
        $email     = Validate::email($body['email'] ?? null);
        $phone     = Validate::phone($body['phone'] ?? null);

        $problems = Security::passwordProblems($body['password'] ?? null, $email, $fullName);
        if ($problems !== []) {
            Response::error('Your password must ' . implode(', ', $problems) . '.');
        }

        $vehicle = null;
        if ($role === 'operator') {
            $vehicleClass = Validate::oneOf($body['vehicleClass'] ?? null, 'Vehicle type', Domain::vehicleIds());
            $spec = Domain::vehicle($vehicleClass);
            $vehicle = [
                'class'    => $vehicleClass,
                'make'     => Validate::str($body['vehicleMake'] ?? null, 'Vehicle make', 1, 60, false),
                'model'    => Validate::str($body['vehicleModel'] ?? null, 'Vehicle model', 1, 60, false),
                'plate'    => Validate::str($body['vehiclePlate'] ?? null, 'Number plate', 2, 16),
                'licence'  => Validate::str($body['licenceNumber'] ?? null, 'Licence number', 1, 40, false),
                'capacity' => (int) (Validate::num($body['capacityKg'] ?? null, 'Payload capacity', 1, 40000, false, true) ?? $spec['capacityKg']),
                'helpers'  => (int) (Validate::num($body['helpersAvailable'] ?? null, 'Helpers available', 0, 6, false, true) ?? 0),
                'tailLift' => Validate::bool($body['hasTailLift'] ?? false),
                'bio'      => Validate::str($body['bio'] ?? null, 'About you', 1, 400, false),
            ];
        }

        if (Database::first('SELECT id FROM users WHERE email = ?', [$email]) !== null) {
            Response::error('An account with that email already exists.', 409);
        }

        $hash = Auth::hashPassword((string) $body['password']);

        $userId = Database::transaction(static function () use ($role, $fullName, $email, $phone, $hash, $vehicle): int {
            $id = Database::insert(
                'INSERT INTO users (role, full_name, email, phone, password_hash, password_changed_at)
                 VALUES (?, ?, ?, ?, ?, NOW())',
                [$role, $fullName, $email, $phone, $hash]
            );

            if ($vehicle !== null) {
                Database::run(
                    'INSERT INTO operator_profiles
                       (user_id, vehicle_class, vehicle_make, vehicle_model, vehicle_plate,
                        capacity_kg, helpers_available, has_tail_lift, licence_number, bio)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                    [
                        $id, $vehicle['class'], $vehicle['make'], $vehicle['model'], $vehicle['plate'],
                        $vehicle['capacity'], $vehicle['helpers'], $vehicle['tailLift'] ? 1 : 0,
                        $vehicle['licence'], $vehicle['bio'],
                    ]
                );
            }
            return $id;
        });

        $user = Database::first('SELECT * FROM users WHERE id = ?', [$userId]);
        Audit::record(Audit::REGISTER, $user, 'user', $userId, $role);

        $this->establishSession($user, 201);
    }

    /* ==================================================================
       Login
       ================================================================== */

    /**
     * POST api/auth/login
     *
     * Accounts with two-factor enabled do not get a session here: they get a
     * short-lived challenge that has to be completed at api/auth/login/2fa.
     */
    public function login(array $body): never
    {
        $ip = Security::clientIp();
        if (!Security::rateLimit('login-ip', $ip, 30, 900)) {
            Response::error('Too many sign-in attempts from here. Try again in a few minutes.', 429);
        }

        $email    = Validate::email($body['email'] ?? null);
        $password = (string) ($body['password'] ?? '');

        if (!Security::rateLimit('login-email', $email, 12, 900)) {
            Response::error('Too many attempts on this account. Try again shortly.', 429);
        }

        $user = Database::first('SELECT * FROM users WHERE email = ?', [$email]);

        // Always spend the same work whether or not the account exists, so
        // this endpoint cannot be used to discover who has an account here.
        $ok = $user !== null
            ? Auth::verifyPassword($password, (string) $user['password_hash'])
            : Auth::burnTime($password);

        if ($user === null || !$ok) {
            $this->recordAttempt($email, false);
            if ($user !== null) {
                $minutes = $this->applyLockout($user);
                Audit::record(
                    $minutes !== null ? Audit::LOGIN_LOCKED : Audit::LOGIN_FAILED,
                    $user,
                    'user',
                    (int) $user['id'],
                    $minutes !== null ? "locked {$minutes}m" : null
                );
            }
            // One message for both cases — never confirm which half was wrong.
            Response::error('Email or password is incorrect.', 401);
        }

        $lockedFor = $this->lockRemainingSeconds($user);
        if ($lockedFor > 0) {
            $this->recordAttempt($email, false);
            Response::error(
                'This account is temporarily locked after repeated failed sign-ins. Try again in '
                . (int) ceil($lockedFor / 60) . ' minute(s).',
                423,
                ['retryAfterSeconds' => $lockedFor]
            );
        }

        if ((int) $user['is_suspended'] === 1) {
            $this->recordAttempt($email, false);
            Response::error(
                $user['suspended_reason']
                    ? 'This account is suspended: ' . $user['suspended_reason']
                    : 'This account is suspended. Contact support.',
                403
            );
        }

        // Password was right: clear the failure state.
        Database::run('UPDATE users SET locked_until = NULL WHERE id = ?', [(int) $user['id']]);
        $this->recordAttempt($email, true);

        if ((int) $user['totp_enabled'] === 1) {
            $challengeId = $this->createChallenge((int) $user['id']);
            Response::json([
                'twoFactorRequired' => true,
                'challengeId'       => $challengeId,
                'expiresInSeconds'  => 300,
            ]);
        }

        Audit::record(Audit::LOGIN_SUCCESS, $user, 'user', (int) $user['id']);
        $this->establishSession($user);
    }

    /** POST api/auth/login/2fa */
    public function loginTwoFactor(array $body): never
    {
        if (!Security::rateLimit('login-2fa', Security::clientIp(), 30, 900)) {
            Response::error('Too many attempts. Try again shortly.', 429);
        }

        $challengeId = Validate::str($body['challengeId'] ?? null, 'Challenge', 8, 100);
        $code        = Validate::str($body['code'] ?? null, 'Code', 6, 20);

        $challenge = $this->consumeChallenge($challengeId);
        if ($challenge === null) {
            Response::error('That sign-in expired. Start again.');
        }

        $user = Database::first('SELECT * FROM users WHERE id = ?', [$challenge['user_id']]);
        if ($user === null || (int) $user['is_suspended'] === 1) {
            Response::error('This account is not available.', 403);
        }

        $counter = Totp::verify(
            (string) $user['totp_secret'],
            $code,
            $user['totp_last_counter'] === null ? null : (int) $user['totp_last_counter']
        );

        if ($counter === null) {
            if (!$this->consumeRecoveryCode($user, $code)) {
                Audit::record(Audit::TWO_FACTOR_FAILED, $user, 'user', (int) $user['id']);
                Response::error('That code is not valid.', 401);
            }
            $detail = 'recovery code';
        } else {
            // Remember the counter so the same code cannot be replayed.
            Database::run('UPDATE users SET totp_last_counter = ? WHERE id = ?', [$counter, (int) $user['id']]);
            $detail = '2fa';
        }

        Audit::record(Audit::LOGIN_SUCCESS, $user, 'user', (int) $user['id'], $detail);
        $this->establishSession(Database::first('SELECT * FROM users WHERE id = ?', [(int) $user['id']]));
    }

    /* ==================================================================
       Session lifecycle
       ================================================================== */

    public function logout(): never
    {
        $user = Auth::requireAuth();
        $session = Auth::session();
        Auth::revokeSession((string) $session['id'], (int) $user['id']);
        Security::clearAuthCookies();
        Audit::record(Audit::LOGOUT, $user, 'user', (int) $user['id']);
        Response::json(['ok' => true]);
    }

    /** GET api/auth/me — rehydrate the session on page load. */
    public function me(): never
    {
        $user = Auth::requireAuth();
        $session = Auth::session();

        $payload = [
            'user'      => Auth::publicUser($user),
            'csrfToken' => $session['csrf_token'],
            'homePath'  => Auth::homePathFor((string) $user['role']),
        ];
        if ($user['role'] === 'operator') {
            $payload['operatorProfile'] = Serialize::operatorProfile((int) $user['id']);
        }
        Response::json($payload);
    }

    public function sessions(): never
    {
        $user = Auth::requireAuth();
        $current = Auth::session();

        Response::json([
            'sessions' => array_map(static fn (array $s): array => [
                'id'         => $s['id'],
                'current'    => $s['id'] === $current['id'],
                'ip'         => $s['ip'],
                'userAgent'  => $s['user_agent'],
                'createdAt'  => $s['created_at'],
                'lastSeenAt' => $s['last_seen_at'],
                'expiresAt'  => $s['expires_at'],
                'revokedAt'  => $s['revoked_at'],
            ], Auth::listSessions((int) $user['id'])),
        ]);
    }

    public function revokeOtherSessions(): never
    {
        $user = Auth::requireAuth();
        $session = Auth::session();
        $count = Auth::revokeAllSessions((int) $user['id'], (int) $user['id'], (string) $session['id']);
        Audit::record(Audit::SESSIONS_REVOKED, $user, 'user', (int) $user['id'], "$count session(s)");
        Response::json(['ok' => true, 'revoked' => $count]);
    }

    /* ==================================================================
       Profile and password
       ================================================================== */

    public function updateProfile(array $body): never
    {
        $user = Auth::requireAuth();

        $fullName = Validate::str($body['fullName'] ?? null, 'Full name', 2, 120, false);
        $phone    = isset($body['phone']) && $body['phone'] !== '' ? Validate::phone($body['phone']) : null;

        if ($fullName === null && $phone === null) {
            Response::error('Nothing to update.');
        }

        Database::run(
            'UPDATE users SET full_name = COALESCE(?, full_name), phone = COALESCE(?, phone) WHERE id = ?',
            [$fullName, $phone, (int) $user['id']]
        );

        Response::json([
            'user' => Auth::publicUser(Database::first('SELECT * FROM users WHERE id = ?', [(int) $user['id']])),
        ]);
    }

    /**
     * POST api/auth/password
     *
     * Changing a password kills every other session — the usual reason
     * somebody changes it is that they think another person has it.
     */
    public function changePassword(array $body): never
    {
        $user = Auth::requireAuth();
        $session = Auth::session();

        $current = Validate::str($body['currentPassword'] ?? null, 'Current password', 1, 200);
        $row = Database::first('SELECT password_hash, email, full_name FROM users WHERE id = ?', [(int) $user['id']]);

        if (!Auth::verifyPassword($current, (string) $row['password_hash'])) {
            Response::error('Current password is incorrect.', 401);
        }

        $problems = Security::passwordProblems(
            $body['newPassword'] ?? null,
            (string) $row['email'],
            (string) $row['full_name']
        );
        if ($problems !== []) {
            Response::error('Your password must ' . implode(', ', $problems) . '.');
        }
        if (Auth::verifyPassword((string) $body['newPassword'], (string) $row['password_hash'])) {
            Response::error('That is your current password. Choose a different one.');
        }

        Database::run(
            'UPDATE users
                SET password_hash = ?, must_change_password = 0,
                    password_changed_at = NOW(), locked_until = NULL
              WHERE id = ?',
            [Auth::hashPassword((string) $body['newPassword']), (int) $user['id']]
        );

        $revoked = Auth::revokeAllSessions((int) $user['id'], (int) $user['id'], (string) $session['id']);
        Audit::record(Audit::PASSWORD_CHANGED, $user, 'user', (int) $user['id'], "$revoked other session(s) ended");

        Response::json(['ok' => true, 'otherSessionsEnded' => $revoked]);
    }

    /* ==================================================================
       Two-factor enrolment
       ================================================================== */

    public function startTwoFactor(): never
    {
        $user = Auth::requireAuth();
        if ((int) $user['totp_enabled'] === 1) {
            Response::error('Two-factor is already switched on.', 409);
        }

        $secret = Totp::generateSecret();
        // Stored but not yet enabled: enrolment only completes once the user
        // proves their authenticator produces matching codes.
        Database::run('UPDATE users SET totp_secret = ? WHERE id = ?', [$secret, (int) $user['id']]);

        Response::json([
            'secret'      => $secret,
            'otpauthUri'  => Totp::provisioningUri($secret, (string) $user['email']),
        ]);
    }

    public function enableTwoFactor(array $body): never
    {
        $user = Auth::requireAuth();
        $code = Validate::str($body['code'] ?? null, 'Code', 6, 10);

        $row = Database::first('SELECT totp_secret FROM users WHERE id = ?', [(int) $user['id']]);
        if ($row === null || $row['totp_secret'] === null) {
            Response::error('Start two-factor setup first.');
        }

        $counter = Totp::verify((string) $row['totp_secret'], $code);
        if ($counter === null) {
            Response::error('That code is not valid. Check your authenticator app.', 401);
        }

        $recoveryCodes = Totp::generateRecoveryCodes();
        Database::run(
            'UPDATE users SET totp_enabled = 1, totp_last_counter = ?, recovery_codes = ? WHERE id = ?',
            [
                $counter,
                json_encode(array_map([Totp::class, 'hashRecoveryCode'], $recoveryCodes)),
                (int) $user['id'],
            ]
        );

        Audit::record(Audit::TWO_FACTOR_ENABLED, $user, 'user', (int) $user['id']);

        // Shown exactly once — only their hashes are kept.
        Response::json(['ok' => true, 'recoveryCodes' => $recoveryCodes]);
    }

    /**
     * POST api/auth/2fa/disable
     *
     * Managers may not turn it off at all: the role that can see every job in
     * the system keeps its second factor.
     */
    public function disableTwoFactor(array $body): never
    {
        $user = Auth::requireAuth();

        if ($user['role'] === 'manager') {
            Response::error(
                'Two-factor authentication is mandatory for manager accounts and cannot be switched off.',
                403
            );
        }

        $password = Validate::str($body['password'] ?? null, 'Password', 1, 200);
        $row = Database::first('SELECT password_hash FROM users WHERE id = ?', [(int) $user['id']]);
        if (!Auth::verifyPassword($password, (string) $row['password_hash'])) {
            Response::error('Password is incorrect.', 401);
        }

        Database::run(
            'UPDATE users
                SET totp_enabled = 0, totp_secret = NULL, totp_last_counter = NULL, recovery_codes = NULL
              WHERE id = ?',
            [(int) $user['id']]
        );

        Audit::record(Audit::TWO_FACTOR_DISABLED, $user, 'user', (int) $user['id']);
        Response::json(['ok' => true]);
    }

    public function policy(): never
    {
        Response::json(['password' => Security::describePasswordPolicy()]);
    }

    /* ==================================================================
       Internals
       ================================================================== */

    private function establishSession(array $user, int $status = 200): never
    {
        $session = Auth::createSession($user);

        Security::setSessionCookie($session['token'], $session['lifetime']);
        Security::setCsrfCookie($session['csrfToken'], $session['lifetime']);

        $payload = [
            'user'      => Auth::publicUser($user),
            'csrfToken' => $session['csrfToken'],
            'homePath'  => Auth::homePathFor((string) $user['role']),
        ];
        if ($user['role'] === 'operator') {
            $payload['operatorProfile'] = Serialize::operatorProfile((int) $user['id']);
        }

        Response::json($payload, $status);
    }

    private function recordAttempt(string $email, bool $succeeded): void
    {
        Database::run(
            'INSERT INTO login_attempts (email, ip, succeeded) VALUES (?, ?, ?)',
            [$email, Security::clientIp(), $succeeded ? 1 : 0]
        );
    }

    /**
     * Progressive lockout: each failure past the threshold doubles the wait,
     * capped at an hour. Slow enough to make online guessing hopeless, short
     * enough that a mistyped password does not lock someone out for the day.
     */
    private function applyLockout(array $user): ?int
    {
        $failures = (int) Database::value(
            'SELECT COUNT(*) FROM login_attempts
              WHERE email = ? AND succeeded = 0 AND created_at > (NOW() - INTERVAL ? MINUTE)',
            [(string) $user['email'], self::FAILURE_WINDOW_MINUTES],
            0
        );
        if ($failures < self::LOCK_THRESHOLD) {
            return null;
        }

        $minutes = (int) min(60, 2 ** ($failures - self::LOCK_THRESHOLD));
        Database::run(
            'UPDATE users SET locked_until = DATE_ADD(NOW(), INTERVAL ? MINUTE) WHERE id = ?',
            [$minutes, (int) $user['id']]
        );
        return $minutes;
    }

    private function lockRemainingSeconds(array $user): int
    {
        if ($user['locked_until'] === null) {
            return 0;
        }
        $remaining = strtotime((string) $user['locked_until']) - time();
        return max(0, $remaining);
    }

    /* ---- Two-factor challenges ------------------------------------- */

    /**
     * A half-finished login is held in the event_queue table with a short
     * expiry rather than a PHP session, so it works the same whether or not
     * the browser has cookies yet.
     */
    private function createChallenge(int $userId): string
    {
        $id = Security::randomToken(24);
        Database::run(
            'INSERT INTO event_queue (user_id, audience, type, payload)
             VALUES (?, \'user\', \'2fa_challenge\', ?)',
            [$userId, json_encode(['challengeId' => $id, 'expiresAt' => time() + 300])]
        );
        return $id;
    }

    private function consumeChallenge(string $challengeId): ?array
    {
        $row = Database::first(
            "SELECT id, user_id, payload FROM event_queue
              WHERE type = '2fa_challenge'
                AND created_at > (NOW() - INTERVAL 5 MINUTE)
                AND payload LIKE ?
              ORDER BY id DESC LIMIT 1",
            ['%"' . $challengeId . '"%']
        );
        if ($row === null) {
            return null;
        }

        $payload = json_decode((string) $row['payload'], true);
        if (!is_array($payload) || ($payload['challengeId'] ?? null) !== $challengeId) {
            return null;
        }
        if ((int) ($payload['expiresAt'] ?? 0) < time()) {
            return null;
        }

        // Single use — burn it so the same challenge id cannot be replayed.
        Database::run('DELETE FROM event_queue WHERE id = ?', [(int) $row['id']]);

        return ['user_id' => (int) $row['user_id']];
    }

    /** Burn a recovery code if it matches. */
    private function consumeRecoveryCode(array $user, string $submitted): bool
    {
        if ($user['recovery_codes'] === null) {
            return false;
        }
        $codes = json_decode((string) $user['recovery_codes'], true);
        if (!is_array($codes)) {
            return false;
        }

        $submittedHash = Totp::hashRecoveryCode($submitted);
        foreach ($codes as $index => $stored) {
            if (hash_equals((string) $stored, $submittedHash)) {
                unset($codes[$index]);
                Database::run(
                    'UPDATE users SET recovery_codes = ? WHERE id = ?',
                    [json_encode(array_values($codes)), (int) $user['id']]
                );
                return true;
            }
        }
        return false;
    }
}
