<?php
/**
 * Operator authentication + management.
 *
 * Sessions, CSRF tokens, login/logout, and CRUD for the `operators` table.
 * Passwords are stored as bcrypt hashes (password_hash/password_verify);
 * all queries use prepared statements.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/** Start the session once, lazily. */
function auth_session(): void
{
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }
}

/* ---- CSRF ---- */

function csrf_token(): string
{
    auth_session();
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(16));
    }
    return $_SESSION['csrf'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="'
        . htmlspecialchars(csrf_token(), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8') . '">';
}

function csrf_verify(?string $token): bool
{
    auth_session();
    return is_string($token) && !empty($_SESSION['csrf']) && hash_equals($_SESSION['csrf'], $token);
}

/* ---- login / session ---- */

/** Validates credentials; on success records the session + last_login. */
function attempt_login(string $username, string $password): bool
{
    $stmt = db()->prepare('SELECT * FROM operators WHERE username = :u LIMIT 1');
    $stmt->execute([':u' => $username]);
    $op = $stmt->fetch();

    if ($op && password_verify($password, $op['password_hash'])) {
        auth_session();
        session_regenerate_id(true);
        $_SESSION['op_id'] = (int) $op['id'];
        db()->prepare('UPDATE operators SET last_login = NOW() WHERE id = :id')
            ->execute([':id' => $op['id']]);
        return true;
    }
    return false;
}

/** @return array<string,mixed>|null */
function current_operator(): ?array
{
    auth_session();
    if (empty($_SESSION['op_id'])) {
        return null;
    }
    $stmt = db()->prepare(
        'SELECT id, username, role, created_at, last_login FROM operators WHERE id = :id'
    );
    $stmt->execute([':id' => $_SESSION['op_id']]);
    $op = $stmt->fetch();
    return $op === false ? null : $op;
}

/** Redirects to the login page unless an operator is signed in. */
function require_login(): array
{
    $op = current_operator();
    if ($op === null) {
        header('Location: login.php');
        exit;
    }
    return $op;
}

function logout(): void
{
    auth_session();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }
    session_destroy();
}

/* ---- operator management ---- */

/** @return list<array<string,mixed>> */
function list_operators(): array
{
    return db()->query(
        'SELECT id, username, role, created_at, last_login FROM operators ORDER BY id ASC'
    )->fetchAll();
}

function create_operator(string $username, string $password, string $role = 'operator'): void
{
    $username = trim($username);
    if ($username === '') {
        throw new InvalidArgumentException('Username is required.');
    }
    if (strlen($password) < 6) {
        throw new InvalidArgumentException('Password must be at least 6 characters.');
    }
    $stmt = db()->prepare(
        'INSERT INTO operators (username, password_hash, role) VALUES (:u, :p, :r)'
    );
    try {
        $stmt->execute([
            ':u' => mb_substr($username, 0, 64),
            ':p' => password_hash($password, PASSWORD_DEFAULT),
            ':r' => $role === 'admin' ? 'admin' : 'operator',
        ]);
    } catch (PDOException $e) {
        if ($e->getCode() === '23000') {
            throw new RuntimeException('That username already exists.');
        }
        throw $e;
    }
}

function delete_operator(int $id): void
{
    $count = (int) db()->query('SELECT COUNT(*) FROM operators')->fetchColumn();
    if ($count <= 1) {
        throw new RuntimeException('Cannot delete the last operator.');
    }
    db()->prepare('DELETE FROM operators WHERE id = :id')->execute([':id' => $id]);
}

function set_operator_password(int $id, string $password): void
{
    if (strlen($password) < 6) {
        throw new InvalidArgumentException('Password must be at least 6 characters.');
    }
    db()->prepare('UPDATE operators SET password_hash = :p WHERE id = :id')
        ->execute([':p' => password_hash($password, PASSWORD_DEFAULT), ':id' => $id]);
}
