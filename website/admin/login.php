<?php
/** Operator sign-in. */
require __DIR__ . '/../includes/bootstrap.php';

if (current_operator()) { redirect('admin/index.php'); }

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    [$ok, $message] = attempt_login((string)($_POST['username'] ?? ''), (string)($_POST['password'] ?? ''));
    if ($ok) {
        flash($message);
        $back = $_SESSION['after_login'] ?? '';
        unset($_SESSION['after_login']);
        /* Only ever return to a plain path inside this application — never to
           "//elsewhere.example" or anything a browser might read as a host. */
        if (is_string($back)
            && str_starts_with($back, BASE_URL . '/admin/')
            && !str_contains($back, '//')
            && !str_contains($back, '\\')
            && preg_match('#^[A-Za-z0-9._~\-/?&=%:,;+!$\'()*@]+$#', $back)) {
            header('Location: ' . $back);
            exit;
        }
        redirect('admin/index.php');
    }
    $error = $message;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Operator sign-in — <?= e(setting('company_name')) ?></title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%230d1521'/%3E%3Ctext x='32' y='44' font-size='34' font-family='Trebuchet MS,sans-serif' font-weight='bold' fill='%23f6a723' text-anchor='middle'%3EL%3C/text%3E%3C/svg%3E">
<link rel="stylesheet" href="<?= e(url('assets/css/styles.css')) ?>">
<link rel="stylesheet" href="<?= e(url('assets/css/admin.css')) ?>">
</head>
<body class="mgr">

<div class="auth-screen">
  <div class="auth-card">
    <span class="logo">
      <span class="logo-mark" aria-hidden="true">LS</span>
      <span class="logo-text">
        <span class="logo-name"><?= e(setting('company_name')) ?></span>
        <span class="logo-tag">Operator area</span>
      </span>
    </span>

    <h1>Sign in</h1>
    <p class="card-sub">Manage vehicles, spare parts, photographs and customer enquiries.</p>

<?php foreach (take_flashes() as $f): ?>
    <div class="form-status show <?= $f['kind'] === 'bad' ? 'bad' : 'ok' ?>"><?= e($f['message']) ?></div>
<?php endforeach; ?>

<?php if ($error): ?>
    <div class="form-status show bad"><?= e($error) ?></div>
<?php endif; ?>

    <form method="post" action="<?= e(url('admin/login.php')) ?>" novalidate style="margin-top:16px">
      <?= csrf_field() ?>
      <div class="field">
        <label for="username">User name</label>
        <input type="text" id="username" name="username" autocomplete="username"
               autocapitalize="none" value="<?= e(old('username')) ?>" required>
      </div>
      <div class="field">
        <label for="password">Password</label>
        <input type="password" id="password" name="password" autocomplete="current-password" required>
      </div>
      <div class="btn-row" style="margin-top:16px">
        <button class="btn btn--primary btn--block" type="submit">Sign in</button>
      </div>
    </form>

    <p style="margin:18px 0 0;font-size:.88rem"><a href="<?= e(url('index.php')) ?>">← Back to the website</a></p>
  </div>
</div>

</body>
</html>
