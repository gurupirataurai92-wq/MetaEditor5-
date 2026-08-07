<?php
/** Operator accounts. Administrators only. */
require __DIR__ . '/../includes/bootstrap.php';

$admin_title = 'Operators';
$tab = 'operators';

$me = require_admin();
$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    csrf_check();
    $action = (string)($_POST['action'] ?? '');
    $targetId = (int)($_POST['id'] ?? 0);

    if ($action === 'create') {
        $username = strtolower(trim((string)($_POST['username'] ?? '')));
        $name     = trim((string)($_POST['name'] ?? ''));
        $email    = trim((string)($_POST['email'] ?? ''));
        $role     = (string)($_POST['role'] ?? 'operator');
        $password = (string)($_POST['password'] ?? '');

        if (!preg_match('/^[a-z0-9._-]{3,60}$/', $username)) {
            $errors['username'] = 'Use 3 to 60 characters: letters, numbers, dot, dash or underscore.';
        } elseif (q_val('SELECT id FROM operators WHERE username = ?', [$username])) {
            $errors['username'] = 'That user name is already taken.';
        }
        if ($name === '') { $errors['name'] = 'Enter the person\'s name.'; }
        if ($email !== '' && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $errors['email'] = 'That email address does not look right.';
        }
        if (strlen($password) < 10) { $errors['password'] = 'Use at least 10 characters.'; }
        if (!in_array($role, ['admin', 'operator'], true)) { $role = 'operator'; }

        if (!$errors) {
            q('INSERT INTO operators (username, name, email, password_hash, role) VALUES (?,?,?,?,?)',
              [$username, $name, $email ?: null, password_hash($password, PASSWORD_DEFAULT), $role]);
            log_activity('created an operator', $username . ' (' . $role . ')');
            flash('Operator "' . $username . '" created.');
            redirect('admin/operators.php');
        }
    }

    if ($action === 'toggle' && $targetId) {
        if ($targetId === (int)$me['id']) {
            flash('You cannot turn off your own account.', 'bad');
        } else {
            q('UPDATE operators SET is_active = 1 - is_active WHERE id = ?', [$targetId]);
            $now = q_one('SELECT username, is_active FROM operators WHERE id = ?', [$targetId]);
            log_activity($now['is_active'] ? 'enabled an operator' : 'disabled an operator', $now['username']);
            flash('Account ' . ($now['is_active'] ? 'enabled' : 'turned off') . '.');
        }
        redirect('admin/operators.php');
    }

    if ($action === 'role' && $targetId) {
        $role = (string)($_POST['role'] ?? 'operator');
        if (!in_array($role, ['admin', 'operator'], true)) { $role = 'operator'; }
        $admins = (int)q_val("SELECT COUNT(*) FROM operators WHERE role='admin' AND is_active=1");
        if ($targetId === (int)$me['id'] && $role !== 'admin' && $admins <= 1) {
            flash('You are the only administrator — promote someone else first.', 'bad');
        } else {
            q('UPDATE operators SET role = ? WHERE id = ?', [$role, $targetId]);
            log_activity('changed an operator role', '#' . $targetId . ' → ' . $role);
            flash('Role updated.');
        }
        redirect('admin/operators.php');
    }

    if ($action === 'reset' && $targetId) {
        $password = (string)($_POST['password'] ?? '');
        if (strlen($password) < 10) {
            flash('The new password needs at least 10 characters.', 'bad');
        } else {
            q('UPDATE operators SET password_hash = ? WHERE id = ?',
              [password_hash($password, PASSWORD_DEFAULT), $targetId]);
            q('DELETE FROM login_attempts WHERE username = (SELECT username FROM operators WHERE id = ?)',
              [$targetId]);
            log_activity('reset an operator password', '#' . $targetId);
            flash('Password changed. Tell them the new one in person, not by email.');
        }
        redirect('admin/operators.php');
    }

    if ($action === 'delete' && $targetId) {
        if ($targetId === (int)$me['id']) {
            flash('You cannot delete your own account.', 'bad');
        } else {
            $victim = q_one('SELECT username FROM operators WHERE id = ?', [$targetId]);
            q('DELETE FROM operators WHERE id = ?', [$targetId]);
            log_activity('deleted an operator', $victim['username'] ?? ('#' . $targetId));
            flash('Operator removed. Their stock entries are kept.');
        }
        redirect('admin/operators.php');
    }
}

$operators = q_all('SELECT * FROM operators ORDER BY role, username');
require __DIR__ . '/_header.php';
?>

<div class="mgr-head">
  <div>
    <h2>Operators</h2>
    <p>Who can sign in and manage the catalogue. Administrators can also manage this page.</p>
  </div>
</div>

<div class="item-list">
<?php foreach ($operators as $o): ?>
  <div class="item-row item-row--wide">
    <div>
      <h3><?= e($o['name']) ?>
        <span class="badge-mini <?= $o['role'] === 'admin' ? 'warn' : '' ?>"><?= e($o['role']) ?></span>
        <?php if (!$o['is_active']): ?><span class="badge-mini none">turned off</span><?php endif; ?>
        <?php if ((int)$o['id'] === (int)$me['id']): ?><span class="badge-mini ok">you</span><?php endif; ?>
      </h3>
      <p class="meta"><?= e($o['username']) ?><?= $o['email'] ? ' · ' . e($o['email']) : '' ?>
        · <?= $o['last_login_at']
              ? 'last signed in ' . e(date('j M Y, H:i', strtotime($o['last_login_at'])))
              : 'never signed in' ?></p>
    </div>

    <div class="item-actions">
      <form method="post" action="<?= e(url('admin/operators.php')) ?>" class="inline-form">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="role">
        <input type="hidden" name="id" value="<?= (int)$o['id'] ?>">
        <select name="role" onchange="this.form.submit()" aria-label="Role for <?= e($o['username']) ?>">
          <option value="operator"<?= $o['role'] === 'operator' ? ' selected' : '' ?>>operator</option>
          <option value="admin"<?= $o['role'] === 'admin' ? ' selected' : '' ?>>admin</option>
        </select>
      </form>

      <form method="post" action="<?= e(url('admin/operators.php')) ?>" class="inline-form">
        <?= csrf_field() ?>
        <input type="hidden" name="action" value="toggle">
        <input type="hidden" name="id" value="<?= (int)$o['id'] ?>">
        <button class="btn btn--ghost btn--sm" type="submit"><?= $o['is_active'] ? 'Turn off' : 'Enable' ?></button>
      </form>

      <details class="reset-pop">
        <summary class="btn btn--ghost btn--sm">Set password</summary>
        <form method="post" action="<?= e(url('admin/operators.php')) ?>" class="reset-form">
          <?= csrf_field() ?>
          <input type="hidden" name="action" value="reset">
          <input type="hidden" name="id" value="<?= (int)$o['id'] ?>">
          <label for="pw<?= (int)$o['id'] ?>">New password (10+ characters)</label>
          <input type="text" id="pw<?= (int)$o['id'] ?>" name="password" autocomplete="off">
          <button class="btn btn--primary btn--sm" type="submit">Set it</button>
        </form>
      </details>

      <?php if ((int)$o['id'] !== (int)$me['id']): ?>
        <form method="post" action="<?= e(url('admin/operators.php')) ?>" class="inline-form"
              onsubmit="return confirm('Remove <?= e(addslashes($o['username'])) ?>?')">
          <?= csrf_field() ?>
          <input type="hidden" name="action" value="delete">
          <input type="hidden" name="id" value="<?= (int)$o['id'] ?>">
          <button class="btn btn--ghost btn--sm" type="submit">Remove</button>
        </form>
      <?php endif; ?>
    </div>
  </div>
<?php endforeach; ?>
</div>

<form class="editor" method="post" action="<?= e(url('admin/operators.php')) ?>" style="margin-top:24px">
  <?= csrf_field() ?>
  <input type="hidden" name="action" value="create">
  <h3>Add an operator</h3>
  <div class="field-row">
    <div class="field">
      <label for="username">User name</label>
      <input type="text" id="username" name="username" autocapitalize="none" value="<?= e(old('username')) ?>">
      <span class="err"><?= e($errors['username'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="name">Full name</label>
      <input type="text" id="name" name="name" value="<?= e(old('name')) ?>">
      <span class="err"><?= e($errors['name'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="email">Email (optional)</label>
      <input type="email" id="email" name="email" value="<?= e(old('email')) ?>">
      <span class="err"><?= e($errors['email'] ?? '') ?></span>
    </div>
    <div class="field">
      <label for="role">Role</label>
      <select id="role" name="role">
        <option value="operator">operator — stock, photos, enquiries</option>
        <option value="admin">admin — everything, including this page</option>
      </select>
      <span class="err"></span>
    </div>
    <div class="field">
      <label for="password">First password (10+ characters)</label>
      <input type="text" id="password" name="password" autocomplete="off">
      <span class="err"><?= e($errors['password'] ?? '') ?></span>
    </div>
    <div class="field">
      <label aria-hidden="true">&nbsp;</label>
      <button class="btn btn--primary btn--block" type="submit">Create operator</button>
    </div>
  </div>
  <p class="card-sub" style="margin-top:12px">The password is shown in plain text here only so you
     can pass it on. It is stored as a hash — nobody, including you, can read it back afterwards.</p>
</form>

<?php require __DIR__ . '/_footer.php'; ?>
