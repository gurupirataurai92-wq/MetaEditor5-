<?php
require_once __DIR__ . '/functions.php';
$pageTitle = $pageTitle ?? 'God Mode';
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?= e($pageTitle) ?> — God Mode Consultant OS</title>
<link rel="stylesheet" href="assets/styles.css">
</head>
<body>
<div class="app">
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-mark">GM</div>
      <div>
        <div class="brand-name">GOD MODE</div>
        <div class="brand-sub">Business Consultant OS</div>
      </div>
    </div>
    <nav id="nav">
      <a href="index.php"        class="<?= nav_active('index.php') ?>"><span class="ico">◈</span> Dashboard</a>
      <a href="ooda.php"         class="<?= nav_active('ooda.php') ?>"><span class="ico">⟳</span> OODA Engine</a>
      <div class="nav-group">CORE PRACTICE</div>
      <a href="consulting.php"   class="<?= nav_active('consulting.php') ?>"><span class="ico">◎</span> Consulting / CRM</a>
      <a href="auditing.php"     class="<?= nav_active('auditing.php') ?>"><span class="ico">✓</span> Auditing</a>
      <a href="accounting.php"   class="<?= nav_active('accounting.php') ?>"><span class="ico">Σ</span> Accounting</a>
      <a href="invoicing.php"    class="<?= nav_active('invoicing.php') ?>"><span class="ico">▤</span> Invoicing</a>
      <a href="microfinance.php" class="<?= nav_active('microfinance.php') ?>"><span class="ico">₵</span> Microfinance</a>
      <div class="nav-group">EXTENDED PRACTICE</div>
      <a href="tax.php"          class="<?= nav_active('tax.php') ?>"><span class="ico">§</span> Tax &amp; Compliance</a>
      <a href="hr.php"           class="<?= nav_active('hr.php') ?>"><span class="ico">☰</span> HR &amp; Payroll</a>
      <a href="risk.php"         class="<?= nav_active('risk.php') ?>"><span class="ico">⚠</span> Risk Register</a>
      <a href="analysis.php"     class="<?= nav_active('analysis.php') ?>"><span class="ico">%</span> Financial Analysis</a>
    </nav>
    <div class="sidebar-foot">
      <form method="post" action="settings.php" style="display:flex;gap:8px;width:100%">
        <select name="currency" onchange="this.form.submit()" title="Display currency">
          <?php foreach (['USD','EUR','GBP','KES','NGN','ZAR','GHS','UGX','TZS','RWF','ZMW','INR','PHP','IDR','BRL','MXN'] as $curOpt): ?>
            <option <?= $curOpt === currency_code() ? 'selected' : '' ?>><?= $curOpt ?></option>
          <?php endforeach; ?>
        </select>
      </form>
    </div>
    <div class="kbd-hint">Press <kbd>Ctrl</kbd>+<kbd>K</kbd> to search everything</div>
  </aside>
  <main class="main" id="main">
    <?= flash() ?>
