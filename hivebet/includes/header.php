<?php
require_once __DIR__ . '/functions.php';
$__user = current_user($pdo);
$__page = $__page ?? 'HiveBet';
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<title><?= e($__page) ?> · HiveBet 🐝</title>
<link rel="stylesheet" href="assets/css/style.css">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🐝</text></svg>">
<!-- Installable mobile app (PWA) -->
<link rel="manifest" href="manifest.webmanifest">
<meta name="theme-color" content="#0d0b06">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="HiveBet">
<link rel="apple-touch-icon" href="assets/icon.svg">
</head>
<body>
<div class="ticker">
  <div class="ticker__track">
    🐝 Welcome to HiveBet — the sweetest odds in the hive &nbsp;•&nbsp; Weekend Mega Jackpot: HC 12,500 &nbsp;•&nbsp; Aviator flying now &nbsp;•&nbsp; Gold market bets settle live &nbsp;•&nbsp; Play responsibly · 18+ &nbsp;•&nbsp;
    🐝 Welcome to HiveBet — the sweetest odds in the hive &nbsp;•&nbsp; Weekend Mega Jackpot: HC 12,500 &nbsp;•&nbsp; Aviator flying now &nbsp;•&nbsp; Gold market bets settle live &nbsp;•&nbsp; Play responsibly · 18+ &nbsp;•&nbsp;
  </div>
</div>

<header class="nav">
  <a class="brand" href="index.php">
    <span class="brand__hex">🐝</span>
    <span class="brand__name">Hive<span>Bet</span></span>
  </a>

  <nav class="nav__links">
    <a href="sports.php">Sports</a>
    <a href="aviator.php">Aviator</a>
    <a href="lucky.php">Lucky Numbers</a>
    <a href="financial.php">Gold Market</a>
    <a href="jackpot.php">Jackpot</a>
    <a href="leaderboard.php">Leaders</a>
  </nav>

  <div class="nav__account">
    <button class="nav__toggle" id="navToggle" aria-label="Open menu" aria-expanded="false">☰</button>
    <?php if ($__user): ?>
      <a href="wallet.php" class="wallet-pill" title="Your balance">
        <span class="wallet-pill__coin">🍯</span>
        <?= money($__user['balance']) ?>
      </a>
      <div class="nav__user">
        <a href="lobby.php" class="nav__hi">Hi, <?= e($__user['username']) ?></a>
        <div class="nav__menu">
          <a href="lobby.php">My Lobby</a>
          <a href="history.php">Bet History</a>
          <a href="wallet.php">Wallet</a>
          <?php if (in_array($__user['role'] ?? 'player', ['staff','owner'], true)): ?><a href="staff.php">Staff dashboard</a><?php endif; ?>
          <?php if (($__user['role'] ?? 'player') === 'owner'): ?><a href="admin.php">Owner console</a><?php endif; ?>
          <a href="logout.php">Log out</a>
        </div>
      </div>
    <?php else: ?>
      <a href="login.php" class="btn btn--ghost">Log in</a>
      <a href="register.php" class="btn btn--gold">Join the Hive</a>
    <?php endif; ?>
  </div>
</header>

<nav class="mobile-menu" id="mobileMenu">
  <a href="sports.php">⚽ Sports</a>
  <a href="aviator.php">✈️ Aviator</a>
  <a href="lucky.php">🎯 Lucky Numbers</a>
  <a href="financial.php">📈 Gold Market</a>
  <a href="jackpot.php">🏆 Jackpot</a>
  <a href="leaderboard.php">👑 Leaders</a>
  <div class="mm-sep"></div>
  <?php if ($__user): ?>
    <a href="lobby.php">🐝 My Lobby</a>
    <a href="wallet.php">🍯 Wallet · <?= money($__user['balance']) ?></a>
    <a href="history.php">📜 Bet History</a>
    <?php if (in_array($__user['role'] ?? 'player', ['staff','owner'], true)): ?><a href="staff.php">🛠️ Staff dashboard</a><?php endif; ?>
    <?php if (($__user['role'] ?? 'player') === 'owner'): ?><a href="admin.php">👑 Owner console</a><?php endif; ?>
    <a href="logout.php">↩ Log out</a>
  <?php else: ?>
    <a href="login.php">Log in</a>
    <a href="register.php">🍯 Join the Hive</a>
  <?php endif; ?>
</nav>

<?php foreach (get_flashes() as $f): ?>
  <div class="flash flash--<?= e($f['type']) ?>"><?= e($f['msg']) ?></div>
<?php endforeach; ?>

<main class="wrap">
