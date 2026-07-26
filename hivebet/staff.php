<?php
require_once __DIR__ . '/includes/functions.php';
require_staff($pdo);
$__page = 'Staff Dashboard';

// Employees can settle fixtures (pays out pending bets).
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    check_csrf();
    try {
        if (($_POST['do'] ?? '') === 'settle_event') {
            $eventId = (int)$_POST['event_id'];
            $result  = $_POST['result'];
            if (!in_array($result, ['home', 'draw', 'away'], true)) throw new RuntimeException('Bad result.');

            $ev = $pdo->prepare('SELECT * FROM events WHERE id = ?');
            $ev->execute([$eventId]);
            $ev = $ev->fetch();
            if (!$ev) throw new RuntimeException('Event not found.');

            $bets = $pdo->prepare('SELECT * FROM bets WHERE game = "sports" AND event_id = ? AND status = "pending"');
            $bets->execute([$eventId]);
            foreach ($bets->fetchAll() as $b) {
                $picked = null;
                if (str_contains($b['selection'], 'Draw'))                    $picked = 'draw';
                elseif (str_contains($b['selection'], $ev['home'] . ' to win')) $picked = 'home';
                elseif (str_contains($b['selection'], $ev['away'] . ' to win')) $picked = 'away';
                settle_bet($pdo, (int)$b['id'], $picked === $result ? 'won' : 'lost', 'Full time: ' . ucfirst($result));
            }
            $pdo->prepare('UPDATE events SET status = "settled", result = ? WHERE id = ?')->execute([$result, $eventId]);
            flash('Settled ' . $ev['home'] . ' vs ' . $ev['away'] . ' as ' . strtoupper($result) . '.', 'success');
        }
    } catch (Throwable $ex) {
        flash($ex->getMessage(), 'error');
    }
    header('Location: staff.php');
    exit;
}

$q = trim($_GET['q'] ?? '');
$m = [
    'players' => (int)$pdo->query("SELECT COUNT(*) FROM users WHERE role = 'player'")->fetchColumn(),
    'bets'    => (int)$pdo->query('SELECT COUNT(*) FROM bets')->fetchColumn(),
    'open'    => (int)$pdo->query("SELECT COUNT(*) FROM bets WHERE status = 'pending'")->fetchColumn(),
    'staked'  => (float)$pdo->query('SELECT COALESCE(SUM(stake),0) FROM bets')->fetchColumn(),
];
$openEvents = $pdo->query('SELECT * FROM events WHERE status = "open" ORDER BY starts_at')->fetchAll();

$ustmt = $pdo->prepare("SELECT * FROM users WHERE role = 'player' AND (username LIKE ? OR email LIKE ?) ORDER BY created_at DESC LIMIT 50");
$like = '%' . $q . '%';
$ustmt->execute([$like, $like]);
$players = $ustmt->fetchAll();

$recent = $pdo->query('SELECT b.*, u.username FROM bets b JOIN users u ON u.id = b.user_id ORDER BY b.id DESC LIMIT 12')->fetchAll();

require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">🛠️ Staff Dashboard</h2>
<p class="muted">Operational view for employees — players, activity and fixture settlement. Revenue &amp; account controls stay in the Owner console.</p>

<div class="stats">
  <div class="stat"><b><?= $m['players'] ?></b><span>Players</span></div>
  <div class="stat"><b><?= $m['bets'] ?></b><span>Bets</span></div>
  <div class="stat"><b><?= $m['open'] ?></b><span>Open bets</span></div>
  <div class="stat"><b><?= money($m['staked']) ?></b><span>Total staked</span></div>
</div>

<h2 class="section-title">Settle open fixtures</h2>
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
  <?php if (!$openEvents): ?><p class="muted center">No open fixtures to settle.</p><?php endif; ?>
</div>

<h2 class="section-title">Players</h2>
<div class="card">
  <form method="get" class="field" style="margin-bottom:14px">
    <input name="q" value="<?= e($q) ?>" placeholder="Search players by name or email…">
  </form>
  <table class="table">
    <tr><th>User</th><th>Email</th><th>Phone</th><th>Balance</th><th>Joined</th></tr>
    <?php foreach ($players as $p): ?>
      <tr>
        <td><b><?= e($p['username']) ?></b></td>
        <td class="muted"><?= e($p['email']) ?></td>
        <td class="muted"><?= e($p['phone'] ?? '—') ?></td>
        <td><?= money($p['balance']) ?></td>
        <td class="muted"><?= date('d M y', strtotime($p['created_at'])) ?></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$players): ?><tr><td colspan="5" class="muted center">No matching players.</td></tr><?php endif; ?>
  </table>
</div>

<h2 class="section-title">Recent activity</h2>
<div class="card">
  <table class="table">
    <tr><th>Player</th><th>Game</th><th>Selection</th><th>Stake</th><th>Odds</th><th>Status</th></tr>
    <?php foreach ($recent as $b): ?>
      <tr>
        <td><?= e($b['username']) ?></td>
        <td><?= e(ucfirst($b['game'])) ?></td>
        <td><?= e($b['selection']) ?></td>
        <td><?= money($b['stake']) ?></td>
        <td><?= number_format($b['odds'], 2) ?></td>
        <td><span class="badge badge--<?= e($b['status']) ?>"><?= e(ucfirst(str_replace('_', ' ', $b['status']))) ?></span></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$recent): ?><tr><td colspan="6" class="muted center">No bets yet.</td></tr><?php endif; ?>
  </table>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
