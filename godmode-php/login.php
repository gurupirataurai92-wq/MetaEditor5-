<?php
require_once __DIR__ . '/includes/functions.php';
require_once __DIR__ . '/includes/auth.php';
auth_boot();

// already signed in? go to the right home
$u = current_user();
if ($u) { header('Location: ' . ($u['role'] === 'distributor' ? 'distributor.php' : 'index.php')); exit; }

$error = '';
if (is_post()) {
    $u = attempt_login(post('email'), post('password'));
    if ($u) {
        header('Location: ' . ($u['role'] === 'distributor' ? 'distributor.php' : 'index.php'));
        exit;
    }
    $error = 'Invalid email or password.';
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Sign in — God Mode Consultant OS</title>
<link rel="stylesheet" href="assets/styles.css">
</head>
<body>
<div class="login-wrap">
  <div class="login-card">
    <div class="brand" style="border:none;padding:0 0 6px">
      <div class="brand-mark">GM</div>
      <div><div class="brand-name">GOD MODE</div><div class="brand-sub">Business Consultant OS</div></div>
    </div>
    <p class="muted" style="font-size:12.5px;margin-bottom:14px">
      One login for everyone — you'll land on your own dashboard.
    </p>
    <?php if ($error): ?><div class="login-error"><?= e($error) ?></div><?php endif; ?>
    <form method="post">
      <label>Email</label><input name="email" type="email" required autofocus>
      <label>Password</label><input name="password" type="password" required>
      <button class="btn btn-primary" style="width:100%;margin-top:16px">Sign in</button>
    </form>
    <div class="login-demo">
      <div><strong>Demo accounts</strong></div>
      <div>Distributor — <span class="mono">distributor@godmode.co</span> / <span class="mono">admin123</span></div>
      <div>Business — <span class="mono">owner@demo.co</span> / <span class="mono">business123</span></div>
    </div>
  </div>
</div>
</body>
</html>
