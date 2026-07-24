<?php
require_once __DIR__ . '/includes/functions.php';
$__page = 'Home';

// live-ish stats for the hero
$totalPlayers = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
$totalBets    = (int)$pdo->query('SELECT COUNT(*) FROM bets')->fetchColumn();
$jackpot      = $pdo->query('SELECT * FROM jackpots WHERE status = "open" ORDER BY draw_at LIMIT 1')->fetch();
$biggestWin   = (float)$pdo->query('SELECT COALESCE(MAX(payout),0) FROM bets')->fetchColumn();

require __DIR__ . '/includes/header.php';
?>

<section class="hero">
  <span class="hero__bees">🐝</span>
  <h1>Where winners <span class="grad">swarm.</span></h1>
  <p>Sports, Aviator, Lucky Numbers, live Gold-Market bets and a growing Mega Jackpot — all in one hive. Sweet odds, instant play, and EcoCash-ready deposits.</p>
  <div class="hero__cta">
    <?php if (is_logged_in()): ?>
      <a href="lobby.php" class="btn btn--gold">Enter the Hive →</a>
      <a href="aviator.php" class="btn btn--ghost">Fly Aviator ✈️</a>
    <?php else: ?>
      <a href="register.php" class="btn btn--gold">Join &amp; get <?= number_format(WELCOME_BONUS) ?> free credits 🍯</a>
      <a href="login.php" class="btn btn--ghost">Log in</a>
    <?php endif; ?>
  </div>

  <div class="stats">
    <div class="stat"><b><?= number_format($totalPlayers) ?></b><span>Players in the hive</span></div>
    <div class="stat"><b><?= money($jackpot['pool'] ?? 0) ?></b><span>Live jackpot pool</span></div>
    <div class="stat"><b><?= number_format($totalBets) ?></b><span>Bets placed</span></div>
    <div class="stat"><b><?= money($biggestWin) ?></b><span>Biggest win</span></div>
  </div>
</section>

<h2 class="section-title">Pick your game</h2>
<div class="grid grid--auto">
  <a class="tile" href="sports.php">
    <span class="tile__tag">HOT</span>
    <span class="tile__emoji">⚽</span>
    <h3>Sports Betting</h3>
    <p>EPL, Champions League &amp; the PSL. Singles and big-margin accumulators.</p>
  </a>
  <a class="tile" href="aviator.php">
    <span class="tile__tag">LIVE</span>
    <span class="tile__emoji">✈️</span>
    <h3>Aviator</h3>
    <p>Watch the multiplier climb — cash out before it flies away.</p>
  </a>
  <a class="tile" href="lucky.php">
    <span class="tile__emoji">🎯</span>
    <h3>Lucky Numbers</h3>
    <p>Pick your numbers, we draw, you win. Simple and sweet.</p>
  </a>
  <a class="tile" href="financial.php">
    <span class="tile__tag">NEW</span>
    <span class="tile__emoji">📈</span>
    <h3>Gold Market</h3>
    <p>Bet UP or DOWN on gold — settled live from real market moves.</p>
  </a>
  <a class="tile" href="jackpot.php">
    <span class="tile__tag">MEGA</span>
    <span class="tile__emoji">🏆</span>
    <h3>Weekend Jackpot</h3>
    <p>Predict the slate, share a pool worth <?= money($jackpot['pool'] ?? 0) ?>.</p>
  </a>
  <a class="tile" href="leaderboard.php">
    <span class="tile__emoji">👑</span>
    <h3>Leaderboard</h3>
    <p>Climb the ranks. Only the busiest bees reach the top.</p>
  </a>
</div>

<h2 class="section-title">Why the hive</h2>
<div class="grid grid--3">
  <div class="card">
    <h3>🍯 Local payments</h3>
    <p class="muted">Designed for EcoCash, cards, cash agents and vouchers — deposit the way your money already moves.</p>
  </div>
  <div class="card">
    <h3>⚡ Instant play</h3>
    <p class="muted">Join in seconds, grab your welcome credits and start betting. No waiting, no fuss.</p>
  </div>
  <div class="card">
    <h3>🔒 Fair &amp; transparent</h3>
    <p class="muted">Provably-fair game mechanics and a full wallet ledger — every credit is accounted for.</p>
  </div>
</div>

<div class="disclaimer">
  🐝 <b>Demo build.</b> HiveBet runs on virtual <b>Hive Credits</b> for demonstration only — there is no real-money gambling and no cash payout. Strictly 18+. Real deployment requires a gaming licence and KYC/AML compliance.
</div>

<?php require __DIR__ . '/includes/footer.php'; ?>
