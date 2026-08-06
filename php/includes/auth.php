<?php
/**
 * Session-based authentication and role-based access control.
 *
 * Passwords are stored only as password_hash() hashes and are NEVER displayed
 * anywhere in the system UI — they are confidential to each operator.
 */
require_once __DIR__ . '/../config/db.php';
require_once __DIR__ . '/functions.php';

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

/** Where each role lands after signing in. */
const ROLE_HOME = [
    'owner'   => 'dashboard.php',
    'manager' => 'staff.php',
    'cashier' => 'pos.php',
];

/** Human labels for roles. */
const ROLE_LABEL = [
    'owner'   => 'Owner',
    'manager' => 'Manager',
    'cashier' => 'Till Operator',
];

/**
 * Which pages each role may open. The login credentials determine the role,
 * and the role determines the dashboard — exactly as required.
 */
const ROLE_PAGES = [
    'owner'   => ['dashboard.php', 'pos.php', 'receipt.php', 'inventory.php', 'staff.php', 'branches.php'],
    'manager' => ['staff.php', 'inventory.php', 'pos.php', 'receipt.php'],
    'cashier' => ['pos.php', 'receipt.php'],
];

/** Attempt to sign in. Returns the user row on success, or null on failure. */
function attempt_login(string $email, string $password): ?array
{
    $stmt = db()->prepare('SELECT * FROM users WHERE email = ? AND active = 1 LIMIT 1');
    $stmt->execute([strtolower(trim($email))]);
    $user = $stmt->fetch();
    if ($user && password_verify($password, $user['password_hash'])) {
        // Refresh the hash if the algorithm/cost changed.
        if (password_needs_rehash($user['password_hash'], PASSWORD_DEFAULT)) {
            $up = db()->prepare('UPDATE users SET password_hash = ? WHERE id = ?');
            $up->execute([password_hash($password, PASSWORD_DEFAULT), $user['id']]);
        }
        return $user;
    }
    return null;
}

/** Store the signed-in user in the session (never the password). */
function login_user(array $user): void
{
    session_regenerate_id(true);
    $_SESSION['uid']    = (int) $user['id'];
    $_SESSION['name']   = $user['name'];
    $_SESSION['role']   = $user['role'];
    $_SESSION['branch'] = (int) $user['branch_id'];
}

/** The current signed-in user, or null. */
function current_user(): ?array
{
    if (empty($_SESSION['uid'])) {
        return null;
    }
    return [
        'id'     => $_SESSION['uid'],
        'name'   => $_SESSION['name'],
        'role'   => $_SESSION['role'],
        'branch' => $_SESSION['branch'] ?? 0,
    ];
}

/** Require a signed-in user, else send to the login screen. */
function require_login(): array
{
    $u = current_user();
    if (!$u) {
        redirect('login.php');
    }
    return $u;
}

/** Require that the current role may open $page, else redirect to its home. */
function require_page(string $page): array
{
    $u = require_login();
    $allowed = ROLE_PAGES[$u['role']] ?? [];
    if (!in_array($page, $allowed, true)) {
        redirect(ROLE_HOME[$u['role']] ?? 'login.php');
    }
    return $u;
}

/** True if the current role may open $page (for hiding nav links). */
function can_open(string $page): bool
{
    $u = current_user();
    if (!$u) {
        return false;
    }
    return in_array($page, ROLE_PAGES[$u['role']] ?? [], true);
}

function logout(): void
{
    $_SESSION = [];
    session_destroy();
}
