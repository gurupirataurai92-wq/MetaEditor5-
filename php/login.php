<?php
/**
 * Sign-in screen. The credentials entered decide the role, and the role
 * decides which dashboard is shown (owner → Dashboard, manager → Staff,
 * till operator → Point of Sale).
 */
require_once __DIR__ . '/includes/auth.php';

// Already signed in? Go straight to the right dashboard.
if ($u = current_user()) {
    redirect(ROLE_HOME[$u['role']] ?? 'login.php');
}

$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $email = $_POST['email'] ?? '';
    $pass  = $_POST['password'] ?? '';
    $user  = attempt_login($email, $pass);
    if ($user) {
        login_user($user);
        redirect(ROLE_HOME[$user['role']] ?? 'login.php');
    }
    $error = 'Those credentials do not match any active account.';
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#0f9d72">
  <title>Sign in — <?= h(APP_NAME) ?></title>
  <link rel="stylesheet" href="assets/style.css">
  <link rel="manifest" href="manifest.php">
</head>
<body class="auth-body">
  <div class="auth-card">
    <div class="brand"><span class="brand-mark">◆</span> <?= h(APP_NAME) ?></div>
    <h1>Welcome back</h1>
    <p class="muted">Sign in — your dashboard is chosen by your account.</p>

    <?php if ($error): ?>
      <div class="alert error"><?= h($error) ?></div>
    <?php endif; ?>

    <form method="post" class="auth-form" autocomplete="off">
      <?= csrf_field() ?>
      <label>Email
        <input type="email" name="email" required autofocus placeholder="you@business.co.zw">
      </label>
      <label>Password
        <input type="password" name="password" required placeholder="••••••••">
      </label>
      <button type="submit" class="btn btn-primary btn-block">Sign in</button>
    </form>

    <details class="demo-note">
      <summary>Demo accounts</summary>
      <p class="muted">Set up by <code>install.php</code>. Passwords are confidential
      inside the system and never displayed there.</p>
      <ul>
        <li><b>Owner</b> — owner@simsai.co.zw</li>
        <li><b>Manager</b> — manager@simsai.co.zw</li>
        <li><b>Till operator</b> — till@simsai.co.zw</li>
      </ul>
    </details>
  </div>
</body>
</html>
