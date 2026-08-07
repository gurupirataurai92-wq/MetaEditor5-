<?php
/** One vehicle, with its photo gallery. */
require __DIR__ . '/includes/bootstrap.php';
require __DIR__ . '/includes/cards.php';

$ref = trim((string)($_GET['ref'] ?? ''));
$v = $ref === '' ? null : q_one('SELECT * FROM vehicles WHERE ref = ? AND is_published = 1', [$ref]);

if (!$v) {
    http_response_code(404);
    $page_title = 'Vehicle not found — ' . setting('company_name');
    $nav = 'vehicles';
    require __DIR__ . '/includes/header.php';
    echo '<section class="section"><div class="wrap"><div class="empty">'
       . '<h3>That vehicle is no longer listed</h3>'
       . '<p>It may have been sold. Our current stock is on the vehicles page.</p>'
       . '<a class="btn btn--primary btn--sm" href="' . e(url('vehicles.php')) . '">See what is available</a>'
       . '</div></div></section>';
    require __DIR__ . '/includes/footer.php';
    exit;
}

$photos = photos_for('vehicle', (int)$v['id']);
$title  = $v['year'] . ' ' . $v['make'] . ' ' . $v['model'];
[$statusText, $statusClass] = status_label($v['status']);

$similar = q_all(
    "SELECT v.*,
            (SELECT p.filename FROM photos p WHERE p.item_type='vehicle' AND p.item_id=v.id
              ORDER BY p.sort_order, p.id LIMIT 1) AS cover
       FROM vehicles v
      WHERE v.is_published = 1 AND v.body = ? AND v.id <> ?
      ORDER BY ABS(v.price - ?) LIMIT 3",
    [$v['body'], $v['id'], $v['price']]
);

$name = setting('company_name');
$page_title = $title . ' — ' . $name;
$page_desc  = $title . ', ' . $v['fuel'] . ', ' . $v['transmission'] . ', ' . km($v['mileage'])
            . '. ' . money($v['price']) . ' CIF.';
$nav = 'vehicles';
require __DIR__ . '/includes/header.php';
?>

  <section class="page-hero page-hero--slim">
    <div class="wrap">
      <p class="crumbs">
        <a href="<?= e(url('index.php')) ?>">Home</a> /
        <a href="<?= e(url('vehicles.php')) ?>">Vehicles</a> / <?= e($v['ref']) ?>
      </p>
      <h1><?= e($title) ?></h1>
      <p>Reference <?= e($v['ref']) ?> · Auction grade <?= e($v['grade']) ?> · <?= e($v['steering']) ?></p>
    </div>
  </section>

  <section class="section">
    <div class="wrap">
      <div class="detail-grid">

        <div>
          <div class="gallery">
            <div class="gallery-main">
              <img id="gallery-main-img" src="<?= e(photo_url($photos[0]['filename'] ?? null, 'assets/img/' . $v['body'] . '.svg')) ?>"
                   alt="<?= e($title) ?>" width="800" height="500">
              <span class="card-flag <?= e($statusClass) ?>"><?= e($statusText) ?></span>
            </div>
            <?php if (count($photos) > 1): ?>
              <div class="gallery-strip">
                <?php foreach ($photos as $i => $ph): ?>
                  <button type="button" class="gallery-thumb<?= $i === 0 ? ' is-active' : '' ?>"
                          data-full="<?= e(photo_url($ph['filename'], 'assets/img/' . $v['body'] . '.svg')) ?>">
                    <img src="<?= e(photo_url($ph['filename'], 'assets/img/' . $v['body'] . '.svg')) ?>"
                         alt="View <?= $i + 1 ?> of <?= e($title) ?>" loading="lazy">
                  </button>
                <?php endforeach; ?>
              </div>
            <?php elseif (!$photos): ?>
              <p class="card-sub" style="margin-top:10px">Photographs of this unit are being added.
                 Ask us for pictures and we will send them straight away.</p>
            <?php endif; ?>
          </div>

          <?php if (!empty($v['note'])): ?>
            <div class="panel" style="margin-top:22px">
              <h3>Notes on this unit</h3>
              <p style="margin:0"><?= e($v['note']) ?></p>
            </div>
          <?php endif; ?>

          <div class="panel" style="margin-top:22px">
            <h3>Full specification</h3>
            <div class="table-scroll" style="margin-top:12px">
              <table>
                <tbody>
                  <tr><th>Reference</th><td><?= e($v['ref']) ?></td></tr>
                  <tr><th>Make and model</th><td><?= e($v['make'] . ' ' . $v['model']) ?></td></tr>
                  <tr><th>Year</th><td><?= (int)$v['year'] ?></td></tr>
                  <tr><th>Body</th><td><?= e(body_label($v['body'])) ?></td></tr>
                  <tr><th>Engine</th><td><?= e($v['engine'] ?: '—') ?></td></tr>
                  <tr><th>Fuel</th><td><?= e($v['fuel']) ?></td></tr>
                  <tr><th>Gearbox</th><td><?= e($v['transmission']) ?></td></tr>
                  <tr><th>Drive</th><td><?= e($v['drive']) ?></td></tr>
                  <tr><th>Mileage</th><td><?= e(km($v['mileage'])) ?></td></tr>
                  <tr><th>Colour</th><td><?= e($v['colour'] ?: '—') ?></td></tr>
                  <tr><th>Auction grade</th><td><?= e($v['grade']) ?></td></tr>
                  <tr><th>Steering</th><td><?= e($v['steering']) ?></td></tr>
                  <tr><th>Availability</th><td><?= e($statusText) ?></td></tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <aside>
          <div class="panel buy-panel">
            <span class="price price--lg"><?= e(money($v['price'])) ?><small>CIF to your port · duty and taxes not included</small></span>
            <div class="btn-row" style="margin-top:18px">
              <a class="btn btn--primary btn--block"
                 href="<?= e(url('contact.php?ref=' . urlencode($v['ref']))) ?>">Request a quote</a>
            </div>
            <div class="btn-row" style="margin-top:10px">
              <a class="btn btn--ghost btn--block" target="_blank" rel="noopener"
                 href="<?= e(wa_link('Hello ' . $name . ', I am interested in the ' . $title . ' (ref ' . $v['ref'] . '). Is it still available?')) ?>">
                 Ask on WhatsApp</a>
            </div>
            <ul class="contact-mini">
              <li>📞 <a href="tel:<?= e(preg_replace('/\s+/', '', setting('phone'))) ?>"><?= e(setting('phone')) ?></a></li>
              <li>✉ <a href="mailto:<?= e(setting('email')) ?>"><?= e(setting('email')) ?></a></li>
            </ul>
          </div>

          <div class="note" style="margin-top:20px">
            <p>The price above is the vehicle, insurance and freight. Import duty is assessed by your
               own customs authority. Ask us and we will estimate the landed cost for your country
               before you commit.</p>
          </div>
        </aside>
      </div>

      <?php if ($similar): ?>
        <div class="section-head" style="margin-top:56px">
          <span class="eyebrow">You might also like</span>
          <h2>Similar units</h2>
        </div>
        <div class="grid grid--3">
          <?php foreach ($similar as $s) { vehicle_card($s); } ?>
        </div>
      <?php endif; ?>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
