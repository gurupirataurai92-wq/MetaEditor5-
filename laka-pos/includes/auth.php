<?php
/**
 * Session + role helpers for LAKA LAKA CHICKEN.
 */

require_once __DIR__ . '/../config/db.php';

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

function current_user(): ?array
{
    return $_SESSION['user'] ?? null;
}

function is_logged_in(): bool
{
    return current_user() !== null;
}

/** Redirect to login unless signed in (optionally restricting to roles). */
function require_login(array $roles = []): void
{
    if (!is_logged_in()) {
        header('Location: index.php');
        exit;
    }
    if ($roles && !in_array(current_user()['role'], $roles, true)) {
        http_response_code(403);
        die('<p style="font-family:sans-serif;padding:2rem">403 — your role does not have access to this page.</p>');
    }
}

function attempt_login(string $username, string $password): bool
{
    $stmt = db()->prepare('SELECT * FROM users WHERE username = ? AND is_active = 1');
    $stmt->execute([$username]);
    $user = $stmt->fetch();
    if ($user && password_verify($password, $user['password_hash'])) {
        unset($user['password_hash']);
        $_SESSION['user'] = $user;
        log_action('login', 'signed in');
        return true;
    }
    return false;
}

function logout(): void
{
    log_action('logout', 'signed out');
    $_SESSION = [];
    session_destroy();
}

function log_action(string $action, string $details = ''): void
{
    $uid = current_user()['id'] ?? null;
    $stmt = db()->prepare('INSERT INTO audit_log (user_id, action, details) VALUES (?,?,?)');
    $stmt->execute([$uid, $action, $details]);
}

/** Landing page for each role after login. */
function role_home(string $role): string
{
    return match ($role) {
        'owner', 'manager' => 'dashboard.php',
        'cook'             => 'kitchen.php',
        default            => 'pos.php',
    };
}

function e(?string $s): string
{
    return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8');
}
