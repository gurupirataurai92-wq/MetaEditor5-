<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Leaderboard';

// Rank by net profit (payouts - stakes) across settled bets
$rows = $pdo->query(
    'SELECT u.username,
            COALESCE(SUM(b.payout),0) - COALESCE(SUM(b.stake),0) AS net,
            COUNT(b.id) AS bets,
            SUM(b.status = "won") AS wins
     FROM users u
     LEFT JOIN bets b ON b.user_id = u.id
     WHERE u.is_admin = 0
     GROUP BY u.id
     ORDER BY net DESC, bets DESC
     LIMIT 20'
)->fetchAll();

require __DIR__ . '/includes/header.php';
?>
<h2 class="section-title">👑 Leaderboard</h2>
<p class="muted">The busiest bees, ranked by net winnings. Climb the comb!</p>

<div class="card mt">
  <table class="table">
    <tr><th>Rank</th><th>Player</th><th>Bets</th><th>Wins</th><th>Net</th></tr>
    <?php foreach ($rows as $i => $r): $medal = ['🥇','🥈','🥉'][$i] ?? ($i + 1); ?>
      <tr>
        <td><b><?= is_string($medal) ? $medal : e((string)$medal) ?></b></td>
        <td><b><?= e($r['username']) ?></b></td>
        <td><?= (int)$r['bets'] ?></td>
        <td><?= (int)$r['wins'] ?></td>
        <td class="<?= $r['net'] >= 0 ? 'pos' : 'neg' ?>"><?= ($r['net'] >= 0 ? '+' : '') . money($r['net']) ?></td>
      </tr>
    <?php endforeach; ?>
    <?php if (!$rows): ?><tr><td colspan="5" class="muted center">No players yet.</td></tr><?php endif; ?>
  </table>
</div>
<?php require __DIR__ . '/includes/footer.php'; ?>
