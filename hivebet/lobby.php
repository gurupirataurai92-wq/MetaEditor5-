<?php
require_once __DIR__ . '/includes/functions.php';
require_login();
$__page = 'My Lobby';
$user = current_user($pdo);

$open = $pdo->prepare('SELECT COUNT(*), COALESCE(SUM(stake),0) FROM bets WHERE user_id = ? AND status = "pending"');
$open->execute([$user['id']]);
[$openCount, $openStake] = $open->fetch(PDO::FETCH_NUM);

$wonStmt = $pdo->prepare('SELECT COALESCE(SUM(payout),0) FROM bets WHERE user_id = ? AND status = "won"');
$wonStmt->execute([$user['id']]);
$totalWon = (float)$wonStmt->fetchColumn();

$recent = $pdo->prepare('SELECT * FROM bets WHERE user_id = ? ORDER BY id DESC LIMIT 6');
$recent->execute([$user['id']]);
$recent = $recent->fetchAll();

require __DIR__ . '/includes/header.php';
?>
<div class="card" style="background:radial-gradient(500px 240px at 90% 0%,rgba(255,176,0,.18),transparent),linear-gradient(180deg,var(--panel),var(--bg-2))">
  <h2>Welcome back, <?= e($user['username']) ?> 🐝</h2>
  <p class="muted">Your hive is buzzing. Here's where things stand.</p>
  <div class="stats" style="margin-top:18px">
    <div class="stat"><b><?= money($user['balance']) ?></b><span>Wallet balance</span></div>
    <div class="stat"><b><?= (int)$openCount ?></b><span>Open bets</span></div>
    <div class="stat"><b><?= money($openStake) ?></b><span>Staked &amp; live</span></div>
    <div class="stat"><b><?= money($totalWon) ?></b><span>Total winnings</span></div>
  </div>
  <div class="hero__cta" style="margin-top:20px">
    <a href="wallet.php" class="btn btn--gold">Deposit / Withdraw 🍯</a>
    <a href="history.php" class="btn btn--ghost">Bet history</a>
  </div>
</div>

<h2 class="section-title">Jump back in</h2>
<div class="grid grid--auto">
  <a class="tile" href="sports.php"><span class="tile__emoji">⚽</span><h3>Sports</h3><p>Back your team.</p></a>
  <a class="tile" href="aviator.php"><span class="tile__emoji">✈️</span><h3>Aviator</h3><p>Cash out in time.</p></a>
  <a class="tile" href="lucky.php"><span class="tile__emoji">🎯</span><h3>Lucky Numbers</h3><p>Pick &amp; win.</p></a>
  <a class="tile" href="financial.php"><span class="tile__emoji">📈</span><h3>Gold Market</h3><p>Up or down?</p></a>
</div>

<h2 class="section-title">Recent bets</h2>
<div class="card">
  <?php if (!$recent): ?>
    <p class="muted center">No bets yet — pick a game above and place your first! 🐝</p>
  <?php else: ?>
    <table class="table">
      <tr><th>Game</th><th>Selection</th><th>Stake</th><th>Odds</th><th>Status</th></tr>
      <?php foreach ($recent as $b): ?>
        <tr>
          <td><?= e(ucfirst($b['game'])) ?></td>
          <td><?= e($b['selection']) ?></td>
          <td><?= money($b['stake']) ?></td>
          <td><?= number_format($b['odds'], 2) ?></td>
          <td><span class="badge badge--<?= e($b['status']) ?>"><?= e(ucfirst($b['status'])) ?></span></td>
        </tr>
      <?php endforeach; ?>
    </table>
    <p class="mt center"><a href="history.php" class="btn btn--ghost btn--sm">See all history →</a></p>
  <?php endif; ?>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
