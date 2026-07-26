<?php
require_once __DIR__ . '/includes/functions.php';
require_once __DIR__ . '/includes/odds_feed.php';
require_owner($pdo);
$__page = 'Owner Console';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    try {
        $do = $_POST['do'] ?? '';

        if ($do === 'settle_event') {
            $eventId = (int)$_POST['event_id'];
            $result  = $_POST['result'];                 // home | draw | away
            if (!in_array($result, ['home','draw','away'], true)) throw new RuntimeException('Bad result.');

            $ev = $pdo->prepare('SELECT * FROM events WHERE id = ?');
            $ev->execute([$eventId]);
            $ev = $ev->fetch();
            if (!$ev) throw new RuntimeException('Event not found.');

            // Settle every pending sports bet on this event
            $bets = $pdo->prepare('SELECT * FROM bets WHERE game = "sports" AND event_id = ? AND status = "pending"');
            $bets->execute([$eventId]);
            $winKey = ['home' => 'to win', 'away' => 'to win', 'draw' => 'Draw'];
            foreach ($bets->fetchAll() as $b) {
                // Selection text ends with "<Team> to win" or "Draw"
                $picked = null;
                if (str_contains($b['selection'], 'Draw')) $picked = 'draw';
                elseif (str_contains($b['selection'], $ev['home'] . ' to win')) $picked = 'home';
                elseif (str_contains($b['selection'], $ev['away'] . ' to win')) $picked = 'away';
                settle_bet($pdo, (int)$b['id'], $picked === $result ? 'won' : 'lost',
                           'Full time: ' . ucfirst($result));
            }
            $pdo->prepare('UPDATE events SET status = "settled", result = ? WHERE id = ?')
                ->execute([$result, $eventId]);
            flash('Settled ' . $ev['home'] . ' vs ' . $ev['away'] . ' as ' . strtoupper($result) . '.', 'success');
        }

        if ($do === 'add_staff') {
            $u = trim($_POST['username'] ?? '');
            $em = trim($_POST['email'] ?? '');
            $pw = $_POST['password'] ?? '';
            $role = in_array($_POST['role'] ?? '', ['staff', 'owner'], true) ? $_POST['role'] : 'staff';
            if (strlen($u) < 3 || !filter_var($em, FILTER_VALIDATE_EMAIL) || strlen($pw) < 6)
                throw new RuntimeException('Enter a valid username (3+), email and password (6+).');
            $dupe = $pdo->prepare('SELECT 1 FROM users WHERE username = ? OR email = ?');
            $dupe->execute([$u, $em]);
            if ($dupe->fetch()) throw new RuntimeException('That username or email is already taken.');
            $pdo->prepare(
                'INSERT INTO users (username, email, password_hash, balance, role, is_admin) VALUES (?,?,?,0,?,1)'
            )->execute([$u, $em, password_hash($pw, PASSWORD_DEFAULT), $role]);
            flash(ucfirst($role) . " account created for {$u}.", 'success');
        }

        if ($do === 'set_role') {
            $uid  = (int)$_POST['user_id'];
            $role = in_array($_POST['role'] ?? '', ['player','staff','owner'], true) ? $_POST['role'] : 'player';
            if ($uid === (int)current_user($pdo)['id']) throw new RuntimeException('You cannot change your own role.');
            $pdo->prepare('UPDATE users SET role = ?, is_admin = ? WHERE id = ?')
                ->execute([$role, $role === 'player' ? 0 : 1, $uid]);
            flash('Role updated.', 'success');
        }

        if ($do === 'remove_user') {
            $uid = (int)$_POST['user_id'];
            if ($uid === (int)current_user($pdo)['id']) throw new RuntimeException('You cannot remove your own account.');
            $pdo->prepare('DELETE FROM users WHERE id = ?')->execute([$uid]);
            flash('Account removed.', 'success');
        }

        if ($do === 'sync_odds') {
            $res = odds_feed_sync($pdo);
            flash("Odds feed synced — fetched {$res['fetched']}, added {$res['inserted']}, refreshed {$res['updated']} lines.", 'success');
        }

        if ($do === 'add_event') {
            $pdo->prepare(
                'INSERT INTO events (category, league, home, away, odds_home, odds_draw, odds_away, starts_at)
                 VALUES (?,?,?,?,?,?,?,?)'
            )->execute([
                $_POST['category'] ?: 'football', $_POST['league'] ?: 'Custom',
                $_POST['home'], $_POST['away'],
                (float)$_POST['odds_home'], ($_POST['odds_draw'] !== '' ? (float)$_POST['odds_draw'] : null),
                (float)$_POST['odds_away'], $_POST['starts_at'] ?: date('Y-m-d H:i:s', time() + 3600),
            ]);
            flash('Event added.', 'success');
        }
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    header('Location: admin.php');
    exit;
}

$openEvents = $pdo->query('SELECT * FROM events WHERE status = "open" ORDER BY starts_at')->fetchAll();
$team = $pdo->query("SELECT * FROM users WHERE role IN ('staff','owner') ORDER BY role DESC, username")->fetchAll();
$stats = [
    'users' => (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn(),
    'bets'  => (int)$pdo->query('SELECT COUNT(*) FROM bets')->fetchColumn(),
    'staked'=> (float)$pdo->query('SELECT COALESCE(SUM(stake),0) FROM bets')->fetchColumn(),
    'paid'  => (float)$pdo->query('SELECT COALESCE(SUM(payout),0) FROM bets')->fetchColumn(),
];
$ggr = $stats['staked'] - $stats['paid'];
require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">👑 Owner Console</h2>
<p class="muted">Full control — revenue, staff accounts and every player. Only owners see this page.</p>

<div class="stats">
  <div class="stat"><b><?= $stats['users'] ?></b><span>Users</span></div>
  <div class="stat"><b><?= $stats['bets'] ?></b><span>Bets</span></div>
  <div class="stat"><b><?= money($stats['staked']) ?></b><span>Total staked</span></div>
  <div class="stat"><b class="<?= $ggr >= 0 ? 'pos' : 'neg' ?>"><?= money($ggr) ?></b><span>House gross (GGR)</span></div>
</div>

<h2 class="section-title">Your team</h2>
<div class="card">
  <table class="table">
    <tr><th>User</th><th>Email</th><th>Role</th><th>Actions</th></tr>
    <?php foreach ($team as $t): $meId = (int)current_user($pdo)['id']; ?>
      <tr>
        <td><b><?= e($t['username']) ?></b></td>
        <td class="muted"><?= e($t['email']) ?></td>
        <td><span class="badge badge--<?= $t['role'] === 'owner' ? 'won' : 'pending' ?>"><?= e(ucfirst($t['role'])) ?></span></td>
        <td>
          <?php if ((int)$t['id'] === $meId): ?><span class="muted">you</span><?php else: ?>
            <form method="post" style="display:inline">
              <?= csrf_field() ?><input type="hidden" name="do" value="set_role"><input type="hidden" name="user_id" value="<?= (int)$t['id'] ?>">
              <input type="hidden" name="role" value="<?= $t['role'] === 'staff' ? 'owner' : 'staff' ?>">
              <button class="btn btn--ghost btn--sm">Make <?= $t['role'] === 'staff' ? 'owner' : 'staff' ?></button>
            </form>
            <form method="post" style="display:inline" data-confirm="Remove this account?">
              <?= csrf_field() ?><input type="hidden" name="do" value="remove_user"><input type="hidden" name="user_id" value="<?= (int)$t['id'] ?>">
              <button class="btn btn--red btn--sm">Remove</button>
            </form>
          <?php endif; ?>
        </td>
      </tr>
    <?php endforeach; ?>
  </table>
</div>

<h2 class="section-title">Add a staff / owner account</h2>
<div class="card">
  <form method="post" class="grid grid--2" style="gap:14px">
    <?= csrf_field() ?>
    <input type="hidden" name="do" value="add_staff">
    <div class="field"><label>Username</label><input name="username" required></div>
    <div class="field"><label>Email</label><input type="email" name="email" required></div>
    <div class="field"><label>Temp password</label><input name="password" required></div>
    <div class="field"><label>Role</label><select name="role"><option value="staff">Staff (employee)</option><option value="owner">Owner</option></select></div>
    <div style="grid-column:1/-1"><button class="btn btn--gold">Create account</button></div>
  </form>
  <p class="muted mt" style="font-size:.82rem">Employees get the Staff dashboard; owners also get this console. Passwords are hashed with bcrypt.</p>
</div>

<h2 class="section-title">Odds feed</h2>
<div class="card">
  <div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap">
    <div style="flex:1;min-width:220px">
      <p>Pull the latest fixtures &amp; odds from the provider stub. New matches are added; existing open lines are refreshed (the demo jitters odds so you can see the line move).</p>
      <p class="muted" style="font-size:.82rem">Automate it with <code>php bin/sync_odds.php</code> on a cron. Swap <code>includes/odds_feed.php</code> for a real Sportradar/BetConstruct call in production.</p>
    </div>
    <form method="post">
      <?= csrf_field() ?>
      <input type="hidden" name="do" value="sync_odds">
      <button class="btn btn--gold">🔄 Sync odds feed</button>
    </form>
  </div>
</div>

<h2 class="section-title">Settle open events</h2>
<div class="card">
  <?php foreach ($openEvents as $ev): ?>
    <form method="post" class="event">
      <?= csrf_field() ?>
      <input type="hidden" name="do" value="settle_event">
      <input type="hidden" name="event_id" value="<?= (int)$ev['id'] ?>">
      <div class="event__teams">
        <div class="pill" style="margin-bottom:6px"><?= e($ev['league']) ?></div>
        <b><?= e($ev['home']) ?> vs <?= e($ev['away']) ?></b>
      </div>
      <div style="display:flex;gap:8px">
        <button class="odds-btn" name="result" value="home">Home won</button>
        <?php if ($ev['odds_draw'] !== null): ?><button class="odds-btn" name="result" value="draw">Draw</button><?php endif; ?>
        <button class="odds-btn" name="result" value="away">Away won</button>
      </div>
    </form>
  <?php endforeach; ?>
  <?php if (!$openEvents): ?><p class="muted center">No open events to settle.</p><?php endif; ?>
</div>

<h2 class="section-title">Add an event</h2>
<div class="card">
  <form method="post" class="grid grid--2" style="gap:14px">
    <?= csrf_field() ?>
    <input type="hidden" name="do" value="add_event">
    <div class="field"><label>League</label><input name="league" placeholder="Castle Lager PSL"></div>
    <div class="field"><label>Category</label><input name="category" value="football"></div>
    <div class="field"><label>Home team</label><input name="home" required></div>
    <div class="field"><label>Away team</label><input name="away" required></div>
    <div class="field"><label>Odds — Home</label><input type="number" step="0.01" name="odds_home" value="2.00" required></div>
    <div class="field"><label>Odds — Draw (blank if none)</label><input type="number" step="0.01" name="odds_draw" value="3.20"></div>
    <div class="field"><label>Odds — Away</label><input type="number" step="0.01" name="odds_away" value="3.40" required></div>
    <div class="field"><label>Starts at</label><input type="datetime-local" name="starts_at"></div>
    <div style="grid-column:1/-1"><button class="btn btn--gold">Add event</button></div>
  </form>
</div>
<div class="disclaimer">Settling an event pays out every pending bet on it and updates player balances instantly.</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
