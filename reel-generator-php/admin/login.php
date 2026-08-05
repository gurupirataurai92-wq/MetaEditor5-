<?php
/** Operator sign-in. */

declare(strict_types=1);

require_once __DIR__ . '/../includes/admin.php';

if (current_operator() !== null) {
    header('Location: index.php');
    exit;
}

$error = null;
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    if (!csrf_verify($_POST['csrf'] ?? null)) {
        $error = 'Session expired — please try again.';
    } elseif (attempt_login((string) ($_POST['username'] ?? ''), (string) ($_POST['password'] ?? ''))) {
        header('Location: index.php');
        exit;
    } else {
        $error = 'Invalid username or password.';
    }
}

admin_header('Sign in', null);
?>
<div class="login-box">
    <h1>Operator sign in</h1>
    <p class="muted">Manage reels, uploads, and operators.</p>

    <?php if ($error !== null): ?>
        <div class="alert"><?= h($error) ?></div>
    <?php endif; ?>

    <form method="post" action="login.php">
        <?= csrf_field() ?>
        <label for="username">Username</label>
        <input id="username" name="username" required autofocus autocomplete="username">
        <label for="password">Password</label>
        <input id="password" name="password" type="password" required autocomplete="current-password">
        <button type="submit">Sign in</button>
    </form>

    <p class="muted small default-hint">
        First run? Default operator is <code>admin</code> / <code>admin123</code> —
        change it right after signing in.
    </p>
    <p class="small"><a class="btn-link" href="../index.php">← Back to site</a></p>
</div>
<?php
admin_footer();
