<?php
/**
 * Shared page shell (top). Pages set $PAGE (current file) and $TITLE before
 * including this. The sidebar is built from the signed-in role's permissions.
 */
require_once __DIR__ . '/auth.php';
$__u = require_login();
$PAGE  = $PAGE  ?? '';
$TITLE = $TITLE ?? APP_NAME;

$nav = [
    ['dashboard.php', 'Dashboard',      '▤'],
    ['pos.php',       'Point of Sale',  '▦'],
    ['inventory.php', 'Inventory',      '▣'],
    ['staff.php',     'Staff & Duty',   '☺'],
    ['branches.php',  'Branches',       '◈'],
];
$__flash = flash_get();
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#0f9d72">
  <title><?= h($TITLE) ?> — <?= h(APP_NAME) ?></title>
  <link rel="stylesheet" href="assets/style.css">
  <link rel="manifest" href="manifest.php">
</head>
<body>
<div class="shell">
  <aside class="sidebar">
    <div class="brand"><span class="brand-mark">◆</span> <span><?= h(APP_NAME) ?></span></div>
    <nav>
      <?php foreach ($nav as [$file, $label, $icon]): ?>
        <?php if (can_open($file)): ?>
          <a class="nav-link<?= $PAGE === $file ? ' active' : '' ?>" href="<?= h($file) ?>">
            <span class="nav-ico"><?= $icon ?></span><?= h($label) ?>
          </a>
        <?php endif; ?>
      <?php endforeach; ?>
    </nav>
    <div class="sidebar-foot">
      <div class="who">
        <div class="who-name"><?= h($__u['name']) ?></div>
        <div class="who-role"><?= h(ROLE_LABEL[$__u['role']] ?? $__u['role']) ?></div>
      </div>
      <a class="btn btn-ghost btn-sm" href="logout.php">Sign out</a>
    </div>
  </aside>

  <main class="content">
    <header class="topbar">
      <button class="menu-toggle" onclick="document.body.classList.toggle('nav-open')" aria-label="Menu">☰</button>
      <h1 class="page-title"><?= h($TITLE) ?></h1>
      <div class="topbar-spacer"></div>
      <span class="pill"><?= h(ROLE_LABEL[$__u['role']] ?? $__u['role']) ?></span>
    </header>

    <?php if ($__flash): ?>
      <div class="alert <?= h($__flash['type']) ?>"><?= h($__flash['msg']) ?></div>
    <?php endif; ?>

    <div class="page">
