<?php
/* ============================================================
   Authentication, roles and usage tracking.

   Two roles share one login form:
     - distributor : SaaS operator; sees subscribers + usage
     - business    : uses the consultant web app
   ============================================================ */

require_once __DIR__ . '/functions.php';

function auth_boot(): void
{
    // CLI-only test hook: never reachable under a real web server (Apache
    // runs the "apache"/"fpm" SAPI, not "cli"), so it cannot bypass auth
    // in production. Used by the offline integration test.
    if (PHP_SAPI === 'cli') {
        $role = getenv('AUTH_TEST_ROLE');
        if ($role) {
            $GLOBALS['__auth_user'] = [
                'id' => 1, 'name' => 'Test User', 'email' => 'test@local',
                'role' => $role, 'business_id' => getenv('AUTH_TEST_BID') ?: null,
            ];
        }
        return;
    }
    if (session_status() !== PHP_SESSION_ACTIVE) {
        session_start();
    }
}

function current_user(): ?array
{
    if (isset($GLOBALS['__auth_user'])) {
        return $GLOBALS['__auth_user'];
    }
    if (empty($_SESSION['uid'])) {
        return null;
    }
    static $cache = null;
    if ($cache === null) {
        $cache = one('SELECT id, business_id, name, email, role FROM users WHERE id = ?', [(int) $_SESSION['uid']]);
    }
    return $cache ?: null;
}

function attempt_login(string $email, string $password): ?array
{
    $u = one('SELECT * FROM users WHERE email = ?', [$email]);
    if ($u && password_verify($password, $u['password_hash'])) {
        $_SESSION['uid'] = (int) $u['id'];
        $now = date('Y-m-d H:i:s');
        q('UPDATE users SET last_seen = ? WHERE id = ?', [$now, $u['id']]);
        if ($u['business_id']) {
            q('UPDATE businesses SET last_active = ? WHERE id = ?', [$now, $u['business_id']]);
        }
        log_usage('login', 'login', (int) $u['id'], $u['business_id'] ? (int) $u['business_id'] : null);
        return $u;
    }
    return null;
}

function logout(): void
{
    $_SESSION = [];
    if (session_status() === PHP_SESSION_ACTIVE) {
        session_destroy();
    }
}

function require_login(): array
{
    $u = current_user();
    if (!$u) {
        header('Location: login.php');
        exit;
    }
    return $u;
}

function require_role(string $role): array
{
    $u = require_login();
    if ($u['role'] !== $role) {
        // send each role to its own home
        header('Location: ' . ($u['role'] === 'distributor' ? 'distributor.php' : 'index.php'));
        exit;
    }
    return $u;
}

function log_usage(string $action, string $page, ?int $uid = null, ?int $bid = null): void
{
    $u = $GLOBALS['__auth_user'] ?? current_user();
    if ($uid === null && $u) { $uid = (int) $u['id']; }
    if ($bid === null && $u && !empty($u['business_id'])) { $bid = (int) $u['business_id']; }
    $now = date('Y-m-d H:i:s');
    insert('INSERT INTO usage_log (user_id, business_id, action, page, at) VALUES (?,?,?,?,?)',
        [$uid, $bid, $action, $page, $now]);
    if ($uid) { q('UPDATE users SET last_seen = ? WHERE id = ?', [$now, $uid]); }
    if ($bid) { q('UPDATE businesses SET last_active = ? WHERE id = ?', [$now, $bid]); }
}

/* Human "time ago" for the distributor console. */
function ago(?string $ts): string
{
    if (!$ts) return 'never';
    $diff = time() - strtotime($ts);
    if ($diff < 0) $diff = 0;
    if ($diff < 60) return 'just now';
    if ($diff < 3600) return floor($diff / 60) . 'm ago';
    if ($diff < 86400) return floor($diff / 3600) . 'h ago';
    return floor($diff / 86400) . 'd ago';
}
