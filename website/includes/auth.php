<?php
/**
 * Operator accounts: sessions, sign-in, roles and the activity log.
 *
 * Passwords are stored only as hashes (password_hash, bcrypt by default).
 * Repeated failures from the same user name and address are locked out for a
 * while, so the sign-in cannot be guessed at speed.
 */

if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

function start_session(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) { return; }

    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => BASE_URL === '' ? '/' : BASE_URL,
        'httponly' => true,                                   // not readable by JavaScript
        'samesite' => 'Lax',                                  // not sent on cross-site posts
        'secure'   => !empty($_SERVER['HTTPS']),
    ]);
    session_name('LYMONDSESS');
    session_start();

    /* Sign an operator out after a spell of inactivity. */
    if (!empty($_SESSION['operator_id'])) {
        $idle = time() - ($_SESSION['seen_at'] ?? time());
        if ($idle > SESSION_IDLE_MINUTES * 60) {
            logout();
            $_SESSION['flash'][] = ['message' => 'You were signed out after a period of inactivity.', 'kind' => 'warn'];
        } else {
            $_SESSION['seen_at'] = time();
        }
    }
}

function client_ip(): string
{
    return substr($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0', 0, 45);
}

/* --------------------------------------------------------------- throttling */

function login_locked(string $username): int
{
    $since = (new DateTimeImmutable('-' . LOGIN_LOCKOUT_MINUTES . ' minutes'))->format('Y-m-d H:i:s');
    $fails = (int)q_val(
        'SELECT COUNT(*) FROM login_attempts WHERE username = ? AND ip = ? AND ok = 0 AND attempted_at > ?',
        [$username, client_ip(), $since]
    );
    return max(0, LOGIN_MAX_ATTEMPTS - $fails);
}

function record_attempt(string $username, bool $ok): void
{
    q('INSERT INTO login_attempts (username, ip, ok) VALUES (?, ?, ?)',
      [substr($username, 0, 60), client_ip(), $ok ? 1 : 0]);
    if ($ok) {
        q('DELETE FROM login_attempts WHERE username = ? AND ip = ?', [$username, client_ip()]);
    }
}

/* ------------------------------------------------------------------- sign in */

/** @return array{0:bool,1:string} success and a message for the operator */
function attempt_login(string $username, string $password): array
{
    $username = trim($username);
    if ($username === '' || $password === '') {
        return [false, 'Enter your user name and password.'];
    }

    if (login_locked($username) <= 0) {
        return [false, 'Too many failed attempts. Try again in ' . LOGIN_LOCKOUT_MINUTES . ' minutes.'];
    }

    $op = q_one('SELECT * FROM operators WHERE username = ?', [$username]);

    /* Verify against a dummy hash when the account is unknown, so a wrong user
       name takes the same time as a wrong password. */
    $hash = $op['password_hash'] ?? '$2y$10$usesomesillystringfore7hnbRJHxXVLeakoG8K30M1p1DV.NlMu';
    $ok = password_verify($password, $hash);

    if (!$op || !$ok) {
        record_attempt($username, false);
        $left = login_locked($username);
        return [false, 'That user name or password is not right.'
                     . ($left > 0 && $left <= 2 ? ' ' . $left . ' attempt' . ($left === 1 ? '' : 's') . ' left.' : '')];
    }

    if (!$op['is_active']) {
        record_attempt($username, false);
        return [false, 'That account has been turned off. Ask an administrator to re-enable it.'];
    }

    if (password_needs_rehash($op['password_hash'], PASSWORD_DEFAULT)) {
        q('UPDATE operators SET password_hash = ? WHERE id = ?',
          [password_hash($password, PASSWORD_DEFAULT), $op['id']]);
    }

    record_attempt($username, true);
    session_regenerate_id(true);                 // new session id on privilege change
    $_SESSION['operator_id'] = (int)$op['id'];
    $_SESSION['seen_at'] = time();
    q('UPDATE operators SET last_login_at = NOW() WHERE id = ?', [$op['id']]);
    log_activity('signed in');

    return [true, 'Welcome back, ' . $op['name'] . '.'];
}

function logout(): void
{
    if (!empty($_SESSION['operator_id'])) { log_activity('signed out'); }
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }
    session_destroy();
    session_start();
    session_regenerate_id(true);
}

/* --------------------------------------------------------------- who is here */

function current_operator(): ?array
{
    static $op = null;
    if ($op !== null) { return $op ?: null; }
    if (empty($_SESSION['operator_id'])) { $op = false; return null; }

    $found = q_one('SELECT * FROM operators WHERE id = ? AND is_active = 1', [$_SESSION['operator_id']]);
    if (!$found) { $_SESSION = []; $op = false; return null; }
    $op = $found;
    return $op;
}

function is_admin(): bool
{
    $op = current_operator();
    return $op !== null && $op['role'] === 'admin';
}

function require_login(): array
{
    $op = current_operator();
    if (!$op) {
        $_SESSION['after_login'] = $_SERVER['REQUEST_URI'] ?? '';
        redirect('admin/login.php');
    }
    return $op;
}

function require_admin(): array
{
    $op = require_login();
    if ($op['role'] !== 'admin') {
        http_response_code(403);
        flash('Only an administrator can open that page.', 'bad');
        redirect('admin/index.php');
    }
    return $op;
}

/* ------------------------------------------------------------- activity log */

function log_activity(string $action, string $detail = ''): void
{
    q('INSERT INTO activity_log (operator_id, action, detail, ip) VALUES (?, ?, ?, ?)', [
        $_SESSION['operator_id'] ?? null,
        substr($action, 0, 80),
        substr($detail, 0, 255),
        client_ip(),
    ]);
}
