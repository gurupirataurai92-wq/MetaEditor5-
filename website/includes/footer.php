<?php
if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }
$name = setting('company_name', 'Lymond Services');
?>
</main>

<footer class="site-footer">
  <div class="wrap footer-grid">
    <div>
      <a class="logo" href="<?= e(url('index.php')) ?>">
        <span class="logo-mark" aria-hidden="true">LS</span>
        <span class="logo-text">
          <span class="logo-name"><?= e($name) ?></span>
          <span class="logo-tag">Imports &amp; Parts</span>
        </span>
      </a>
      <p style="margin-top:14px">Importers of inspected Japanese vehicles and suppliers of genuine,
         OEM and aftermarket spare parts — from a single clip to a complete engine.</p>
      <p><a class="btn btn--accent btn--sm" target="_blank" rel="noopener"
            href="<?= e(wa_link('Hello ' . $name . ', I would like a quote.')) ?>">Chat on WhatsApp</a></p>
    </div>

    <div>
      <h4>Vehicles</h4>
      <ul>
        <li><a href="<?= e(url('vehicles.php')) ?>">All stock</a></li>
        <li><a href="<?= e(url('vehicles.php?body=suv')) ?>">SUVs &amp; 4WD</a></li>
        <li><a href="<?= e(url('vehicles.php?body=pickup')) ?>">Pickups</a></li>
        <li><a href="<?= e(url('vehicles.php?body=van')) ?>">Vans &amp; MPVs</a></li>
        <li><a href="<?= e(url('vehicles.php?body=truck')) ?>">Trucks</a></li>
      </ul>
    </div>

    <div>
      <h4>Spare parts</h4>
      <ul>
<?php foreach (q_all('SELECT slug, name FROM part_categories ORDER BY sort_order LIMIT 4') as $c): ?>
        <li><a href="<?= e(url('parts.php?category=' . urlencode($c['slug']))) ?>"><?= e($c['name']) ?></a></li>
<?php endforeach; ?>
        <li><a href="<?= e(url('parts.php')) ?>">Full catalogue</a></li>
      </ul>
    </div>

    <div>
      <h4>Company</h4>
      <ul>
        <li><a href="<?= e(url('about.php')) ?>">How importing works</a></li>
        <li><a href="<?= e(url('about.php#faq')) ?>">FAQ</a></li>
        <li><a href="<?= e(url('contact.php')) ?>">Contact &amp; location</a></li>
        <li><a href="<?= e(url('admin/')) ?>">Operator sign-in</a></li>
      </ul>
    </div>
  </div>

  <div class="wrap footer-bottom">
    <span>© <?= date('Y') ?> <?= e($name) ?>. All rights reserved.</span>
    <span><?= e(setting('address')) ?></span>
  </div>

  <div class="disclaimer">
    <div class="wrap">
      <p><?= e($name) ?> is an independent importer and parts supplier. We source vehicles from
         Japanese exporters and auction houses, including BE&nbsp;FORWARD, but we are not owned by,
         affiliated with or an official agent of any of them. All product names and trademarks belong
         to their respective owners. Prices are indicative, exclude import duty and taxes, and are
         subject to confirmation at the time of order.</p>
    </div>
  </div>
</footer>

<script src="<?= e(url('assets/js/site.js')) ?>"></script>
</body>
</html>
