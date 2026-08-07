<?php
/** The signed-in operator's own account. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'My account';
$tab = 'account';

$op = require_login();
$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string)($_POST['action'] ?? '');

    if ($action === 'details') {
        $name  = trim((string)($_POST['name'] ?? ''));
        $email = trim((string)($_POST['email'] ?? ''));
        if ($name === '') { $errors['name'] = 'Enter your name.'; }
        if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $errors['email'] = 'That email address does not look right.';
        }
        if (!$errors) {
            q('UPDATE operators SET name = ?, email = ? WHERE id = ?', [$name, $email ?: null, $op['id']]);
            log_activity('updated their own details');
            flash('Your details are saved.');
            redirect('admin/account.php');
        }
    }

    if ($action === 'password') {
        $current = (string)($_POST['current'] ?? '');
        $new     = (string)($_POST['new'] ?? '');
        $again   = (string)($_POST['again'] ?? '');

        if (!password_verify($current, $op['password_hash'])) {
            $errors['current'] = 'That is not your current password.';
        }
        if (strlen($new) < 10)  { $errors['new'] = 'Use at least 10 characters.'; }
        if ($new !== $again)    { $errors['again'] = 'The two new passwords do not match.'; }
        if ($new === $current)  { $errors['new'] = 'Choose a password you have not used here before.'; }

        if (!$errors) {
            q('UPDATE operators SET password_hash = ? WHERE id = ?',
              [password_hash($new, PASSWORD_DEFAULT), $op['id']]);
            log_activity('changed their own password');
            flash('Password changed.');
            redirect('admin/account.php');
        }
    }
}

require __DIR__ . '/_header.php';
?>

<div class="mgr-head">
  <div>
    <h2>My account</h2>
    <p>Signed in as <b><?= e($op['username']) ?></b> (<?= e($op['role']) ?>).</p>
  </div>
</div>

<div class="grid grid--2 grid--top">
  <form class="editor" method="post" action="<?= e(url('admin/account.php')) ?>">
    <?= csrf_field() ?>
    <input type="hidden" name="action" value="details">
    <h3>Your details</h3>
    <div class="field">
      <label for="name">Name</label>
      <input type="text" id="name" name="name" value="<?= e($_POST['name'] ?? $op['name']) ?>">
      <span class="err"><?= e($errors['name'] ?? '') ?></span>
    </div>
    <div class="field" style="margin-top:12px">
      <label for="email">Email</label>
      <input type="email" id="email" name="email" value="<?= e($_POST['email'] ?? $op['email'] ?? '') ?>">
      <span class="err"><?= e($errors['email'] ?? '') ?></span>
    </div>
    <div class="editor-foot">
      <button class="btn btn--primary" type="submit">Save details</button>
    </div>
  </form>

  <form class="editor" method="post" action="<?= e(url('admin/account.php')) ?>">
    <?= csrf_field() ?>
    <input type="hidden" name="action" value="password">
    <input type="text" name="username" value="<?= e($op['username']) ?>" autocomplete="username" hidden aria-hidden="true" tabindex="-1">
    <h3>Change your password</h3>
    <div class="field">
      <label for="current">Current password</label>
      <input type="password" id="current" name="current" autocomplete="current-password">
      <span class="err"><?= e($errors['current'] ?? '') ?></span>
    </div>
    <div class="field" style="margin-top:12px">
      <label for="new">New password (10+ characters)</label>
      <input type="password" id="new" name="new" autocomplete="new-password">
      <span class="err"><?= e($errors['new'] ?? '') ?></span>
    </div>
    <div class="field" style="margin-top:12px">
      <label for="again">Repeat the new password</label>
      <input type="password" id="again" name="again" autocomplete="new-password">
      <span class="err"><?= e($errors['again'] ?? '') ?></span>
    </div>
    <div class="editor-foot">
      <button class="btn btn--primary" type="submit">Change password</button>
    </div>
  </form>
</div>

<div class="editor">
  <h3>Your recent activity</h3>
  <ul class="activity">
    <?php foreach (q_all('SELECT * FROM activity_log WHERE operator_id = ? ORDER BY happened_at DESC LIMIT 15', [$op['id']]) as $a): ?>
      <li><span class="when"><?= e(date('j M H:i', strtotime($a['happened_at']))) ?></span>
          <span><?= e($a['action']) ?><?= $a['detail'] ? ' — ' . e($a['detail']) : '' ?></span></li>
    <?php endforeach; ?>
  </ul>
</div>

<?php require __DIR__ . '/_footer.php'; ?>
