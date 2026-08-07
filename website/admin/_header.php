<?php
/** Admin chrome. Requires an operator; set $admin_title and $tab first. */
if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

$op = require_login();
$tab = $tab ?? '';
$newEnquiries = (int)q_val("SELECT COUNT(*) FROM enquiries WHERE status = 'new'");
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title><?= e($admin_title ?? 'Operator area') ?> — <?= e(setting('company_name')) ?></title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%230d1521'/%3E%3Ctext x='32' y='44' font-size='34' font-family='Trebuchet MS,sans-serif' font-weight='bold' fill='%23f6a723' text-anchor='middle'%3EL%3C/text%3E%3C/svg%3E">
<link rel="stylesheet" href="<?= e(url('assets/css/styles.css')) ?>">
<link rel="stylesheet" href="<?= e(url('assets/css/admin.css')) ?>">
</head>
<body class="mgr">

<div class="mgr-bar">
  <div class="wrap">
    <span class="logo">
      <span class="logo-mark" aria-hidden="true">LS</span>
      <span class="logo-text">
        <span class="logo-name"><?= e(setting('company_name')) ?></span>
        <span class="logo-tag">Operator area</span>
      </span>
    </span>
    <span class="spacer"></span>
    <span class="pill"><?= e($op['name']) ?> · <?= e($op['role']) ?></span>
    <a class="btn btn--ghost btn--sm" href="<?= e(url('index.php')) ?>" target="_blank" rel="noopener">View site</a>
    <a class="btn btn--ghost btn--sm" href="<?= e(url('admin/logout.php')) ?>">Sign out</a>
  </div>
</div>

<nav class="mgr-tabs">
  <a class="mgr-tab" aria-selected="<?= $tab === 'dash' ? 'true' : 'false' ?>" href="<?= e(url('admin/index.php')) ?>">Dashboard</a>
  <a class="mgr-tab" aria-selected="<?= $tab === 'vehicles' ? 'true' : 'false' ?>" href="<?= e(url('admin/vehicles.php')) ?>">Vehicles</a>
  <a class="mgr-tab" aria-selected="<?= $tab === 'parts' ? 'true' : 'false' ?>" href="<?= e(url('admin/parts.php')) ?>">Spare parts</a>
  <a class="mgr-tab" aria-selected="<?= $tab === 'enquiries' ? 'true' : 'false' ?>" href="<?= e(url('admin/enquiries.php')) ?>">
     Enquiries<?php if ($newEnquiries): ?> <span class="badge-mini warn"><?= $newEnquiries ?> new</span><?php endif; ?></a>
  <a class="mgr-tab" aria-selected="<?= $tab === 'settings' ? 'true' : 'false' ?>" href="<?= e(url('admin/settings.php')) ?>">Company details</a>
<?php if (is_admin()): ?>
  <a class="mgr-tab" aria-selected="<?= $tab === 'operators' ? 'true' : 'false' ?>" href="<?= e(url('admin/operators.php')) ?>">Operators</a>
<?php endif; ?>
  <a class="mgr-tab" aria-selected="<?= $tab === 'account' ? 'true' : 'false' ?>" href="<?= e(url('admin/account.php')) ?>">My account</a>
</nav>

<section class="mgr-panel">
  <div class="wrap">
<?php foreach (take_flashes() as $f): ?>
    <div class="form-status show <?= $f['kind'] === 'bad' ? 'bad' : 'ok' ?>" style="margin-bottom:18px"><?= e($f['message']) ?></div>
<?php endforeach; ?>
