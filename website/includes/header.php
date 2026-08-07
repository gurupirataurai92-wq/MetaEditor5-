<?php
/** Public site header. Set $page_title, $page_desc and $nav before including. */
if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

$co   = settings();
$nav  = $nav ?? '';
$name = setting('company_name', 'Lymond Services');
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= e($page_title ?? $name) ?></title>
<meta name="description" content="<?= e($page_desc ?? 'Imported Japanese vehicles and spare parts, small to big.') ?>">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%23e63946'/%3E%3Ctext x='32' y='44' font-size='34' font-family='Trebuchet MS,sans-serif' font-weight='bold' fill='%23fff' text-anchor='middle'%3EL%3C/text%3E%3C/svg%3E">
<link rel="stylesheet" href="<?= e(url('assets/css/styles.css')) ?>">
</head>
<body>
<a class="skip-link" href="#main">Skip to content</a>

<header class="site-header">
  <div class="topbar">
    <div class="wrap">
      <div class="topbar-contact">
        <span>📞 <a href="tel:<?= e(preg_replace('/\s+/', '', setting('phone'))) ?>"><?= e(setting('phone')) ?></a></span>
        <span>✉ <a href="mailto:<?= e(setting('email')) ?>"><?= e(setting('email')) ?></a></span>
      </div>
      <span><?= e(setting('hours')) ?></span>
    </div>
  </div>

  <div class="wrap nav">
    <a class="logo" href="<?= e(url('index.php')) ?>">
      <span class="logo-mark" aria-hidden="true">LS</span>
      <span class="logo-text">
        <span class="logo-name"><?= e($name) ?></span>
        <span class="logo-tag">Imports &amp; Parts</span>
      </span>
    </a>

    <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="nav-menu" aria-label="Toggle navigation">☰</button>

    <div class="nav-menu" id="nav-menu">
      <ul class="nav-links">
        <li><a href="<?= e(url('index.php')) ?>"<?= $nav === 'home' ? ' aria-current="page"' : '' ?>>Home</a></li>
        <li><a href="<?= e(url('vehicles.php')) ?>"<?= $nav === 'vehicles' ? ' aria-current="page"' : '' ?>>Vehicles</a></li>
        <li><a href="<?= e(url('parts.php')) ?>"<?= $nav === 'parts' ? ' aria-current="page"' : '' ?>>Spare parts</a></li>
        <li><a href="<?= e(url('about.php')) ?>"<?= $nav === 'about' ? ' aria-current="page"' : '' ?>>How it works</a></li>
        <li><a href="<?= e(url('contact.php')) ?>"<?= $nav === 'contact' ? ' aria-current="page"' : '' ?>>Contact</a></li>
      </ul>
      <div class="nav-cta">
        <a class="btn btn--accent btn--sm" target="_blank" rel="noopener"
           href="<?= e(wa_link('Hello ' . $name . ', I would like a quote.')) ?>">WhatsApp us</a>
      </div>
    </div>
  </div>
</header>

<main id="main">
<?php foreach (take_flashes() as $f): ?>
  <div class="wrap" style="padding-top:18px">
    <div class="form-status show <?= $f['kind'] === 'bad' ? 'bad' : 'ok' ?>"><?= e($f['message']) ?></div>
  </div>
<?php endforeach; ?>
