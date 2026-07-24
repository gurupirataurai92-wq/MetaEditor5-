<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Log in';
if (is_logged_in()) { header('Location: lobby.php'); exit; }

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $id   = trim($_POST['identity'] ?? '');
    $pass = $_POST['password'] ?? '';

    $stmt = $pdo->prepare('SELECT * FROM users WHERE username = ? OR email = ?');
    $stmt->execute([$id, $id]);
    $user = $stmt->fetch();

    if ($user && password_verify($pass, $user['password_hash'])) {
        $_SESSION['user_id'] = (int)$user['id'];
        flash('Welcome back, ' . $user['username'] . '! 🐝', 'success');
        header('Location: lobby.php');
        exit;
    }
    $error = 'Incorrect login details. Try again.';
}

require __DIR__ . '/includes/header.php';
?>
<div class="card form">
  <h2>🐝 Log in</h2>
  <?php if ($error): ?><div class="flash flash--error" style="margin:12px 0"><?= e($error) ?></div><?php endif; ?>
  <form method="post" class="mt">
    <?= csrf_field() ?>
    <div class="field"><label>Username or email</label><input name="identity" required autofocus></div>
    <div class="field"><label>Password</label><input type="password" name="password" required></div>
    <button class="btn btn--gold btn--block">Log in</button>
  </form>
  <p class="auth-switch">New here? <a href="register.php">Join the Hive</a></p>
  <div class="disclaimer">Demo accounts — <b>admin / admin123</b> · <b>beeplayer / play123</b></div>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
