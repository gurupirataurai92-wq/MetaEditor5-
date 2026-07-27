<?php
require_once __DIR__ . '/includes/auth.php';

if (is_logged_in()) {
    header('Location: ' . role_home(current_user()['role']));
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';
    if (attempt_login($username, $password)) {
        header('Location: ' . role_home(current_user()['role']));
        exit;
    }
    $error = 'Wrong username or password. Try again.';
}
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Staff sign in · LAKA LAKA CHICKEN</title>
<link rel="stylesheet" href="assets/style.css">
</head>
<body class="login-body">
<div class="login-card">
  <img src="assets/food/bucket.svg" alt="" class="login-logo" width="76" height="76">
  <div class="login-brand">LAKA&nbsp;LAKA<br>CHICKEN<span>Staff Portal</span></div>
  <?php if ($error): ?><p class="login-error"><?= e($error) ?></p><?php endif; ?>
  <form method="post" autocomplete="off">
    <label>Username
      <input name="username" required autofocus value="<?= e($_POST['username'] ?? '') ?>">
    </label>
    <label>Password
      <input name="password" type="password" required>
    </label>
    <button type="submit">Sign in</button>
  </form>
  <div class="login-hint">
    <b>Demo logins</b>
    owner / owner123 · manager / manager123<br>
    cashier / cashier123 · cook / cook123
  </div>
  <p class="login-back"><a href="index.php">&larr; Back to laka laka chicken.com</a></p>
</div>
</body>
</html>
