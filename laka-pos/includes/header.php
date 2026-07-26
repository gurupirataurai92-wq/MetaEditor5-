<?php
/** Shared page chrome. Expects $page_title and an active session. */
require_once __DIR__ . '/auth.php';
$u = current_user();
$active = basename($_SERVER['PHP_SELF']);

/** Nav items available to each role. */
$nav = [
    'dashboard.php' => ['Dashboard', ['owner', 'manager']],
    'pos.php'       => ['Point of Sale', ['owner', 'manager', 'cashier']],
    'kitchen.php'   => ['Kitchen', ['owner', 'manager', 'cook']],
    'orders.php'    => ['Orders', ['owner', 'manager', 'cashier']],
    'inventory.php' => ['Inventory', ['owner', 'manager']],
    'menu.php'      => ['Menu', ['owner', 'manager']],
];
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($page_title ?? 'LAKA LAKA CHICKEN') ?> · LAKA LAKA CHICKEN</title>
<link rel="stylesheet" href="assets/style.css">
</head>
<body>
<header class="topbar">
  <div class="brand">
    <img src="assets/food/bucket.svg" alt="" class="brand-logo" width="34" height="34">
    <span class="brand-word">LAKA&nbsp;LAKA&nbsp;CHICKEN</span>
  </div>
  <nav class="mainnav">
    <?php foreach ($nav as $file => [$label, $roles]): ?>
      <?php if ($u && in_array($u['role'], $roles, true)): ?>
        <a href="<?= $file ?>" class="<?= $active === $file ? 'on' : '' ?>"><?= e($label) ?></a>
      <?php endif; ?>
    <?php endforeach; ?>
  </nav>
  <div class="who">
    <span class="uname"><?= e($u['full_name'] ?? '') ?></span>
    <span class="role"><?= e($u['role'] ?? '') ?></span>
    <a class="logout" href="logout.php">Log out</a>
  </div>
</header>
<div class="stripe"></div>
<main class="page">
