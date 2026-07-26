<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Join';
if (is_logged_in()) { header('Location: lobby.php'); exit; }

$errors = [];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    $username = trim($_POST['username'] ?? '');
    $email    = trim($_POST['email'] ?? '');
    $phone    = trim($_POST['phone'] ?? '');
    $pass     = $_POST['password'] ?? '';
    $pass2    = $_POST['password2'] ?? '';

    if (strlen($username) < 3)                 $errors[] = 'Username must be at least 3 characters.';
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) $errors[] = 'Enter a valid email address.';
    if (strlen($pass) < 6)                     $errors[] = 'Password must be at least 6 characters.';
    if ($pass !== $pass2)                       $errors[] = 'Passwords do not match.';

    if (!$errors) {
        $exists = $pdo->prepare('SELECT 1 FROM users WHERE username = ? OR email = ?');
        $exists->execute([$username, $email]);
        if ($exists->fetch()) {
            $errors[] = 'That username or email is already taken.';
        } else {
            // First ever account becomes the owner automatically.
            $isFirst = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn() === 0;
            $role    = $isFirst ? 'owner' : 'player';
            $isAdmin = $isFirst ? 1 : 0;
            $stmt = $pdo->prepare(
                'INSERT INTO users (username, email, phone, password_hash, balance, role, is_admin)
                 VALUES (?,?,?,?,?,?,?)'
            );
            $stmt->execute([$username, $email, $phone,
                password_hash($pass, PASSWORD_DEFAULT), WELCOME_BONUS, $role, $isAdmin]);
            $uid = (int)$pdo->lastInsertId();

            $pdo->prepare(
                'INSERT INTO transactions (user_id, type, method, amount, balance_after, note)
                 VALUES (?,?,?,?,?,?)'
            )->execute([$uid, 'bonus', 'demo', WELCOME_BONUS, WELCOME_BONUS, 'Welcome bonus']);

            $_SESSION['user_id'] = $uid;
            flash('Welcome to the hive, ' . $username . '! Enjoy ' . money(WELCOME_BONUS) . ' on us. 🍯', 'success');
            header('Location: lobby.php');
            exit;
        }
    }
}

require __DIR__ . '/includes/header.php';
?>
<div class="card form">
  <h2>🐝 Join the Hive</h2>
  <p class="muted">Create an account and get <b><?= money(WELCOME_BONUS) ?></b> in free demo credits.</p>

  <?php foreach ($errors as $err): ?><div class="flash flash--error" style="margin:12px 0"><?= e($err) ?></div><?php endforeach; ?>

  <form method="post" class="mt">
    <?= csrf_field() ?>
    <div class="field"><label>Username</label><input name="username" value="<?= e($_POST['username'] ?? '') ?>" required></div>
    <div class="field"><label>Email</label><input type="email" name="email" value="<?= e($_POST['email'] ?? '') ?>" required></div>
    <div class="field"><label>Phone (EcoCash number)</label><input name="phone" placeholder="+263 7X XXX XXXX" value="<?= e($_POST['phone'] ?? '') ?>"></div>
    <div class="field"><label>Password</label><input type="password" name="password" required></div>
    <div class="field"><label>Confirm password</label><input type="password" name="password2" required></div>
    <button class="btn btn--gold btn--block">Create my account 🍯</button>
  </form>
  <p class="auth-switch">Already buzzing? <a href="login.php">Log in</a></p>
  <div class="disclaimer">By joining you confirm you are 18+. Play-money demo — no real gambling.</div>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
