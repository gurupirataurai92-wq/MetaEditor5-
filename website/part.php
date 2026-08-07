<?php
/** One spare part, with its photo gallery. */
require __DIR__ . '/includes/bootstrap.php';
require __DIR__ . '/includes/cards.php';

$ref = trim((string)($_GET['ref'] ?? ''));
$p = $ref === '' ? null : q_one(
    'SELECT p.*, c.slug AS category_slug, c.name AS category_name
       FROM parts p JOIN part_categories c ON c.id = p.category_id
      WHERE p.ref = ? AND p.is_published = 1', [$ref]);

if (!$p) {
    http_response_code(404);
    $page_title = 'Part not found — ' . setting('company_name');
    $nav = 'parts';
    require __DIR__ . '/includes/header.php';
    echo '<section class="section"><div class="wrap"><div class="empty">'
       . '<h3>That part is no longer listed</h3>'
       . '<p>Send us the chassis number and we will source it for you.</p>'
       . '<a class="btn btn--primary btn--sm" href="' . e(url('parts.php')) . '">Back to the catalogue</a>'
       . '</div></div></section>';
    require __DIR__ . '/includes/footer.php';
    exit;
}

$photos = photos_for('part', (int)$p['id']);
[$typeText, $typeClass] = part_type_label($p['type']);
$inStock = $p['stock'] === 'in-stock';

$related = q_all(
    "SELECT p.*, c.slug AS category_slug,
            (SELECT ph.filename FROM photos ph WHERE ph.item_type='part' AND ph.item_id=p.id
              ORDER BY ph.sort_order, ph.id LIMIT 1) AS cover
       FROM parts p JOIN part_categories c ON c.id = p.category_id
      WHERE p.is_published = 1 AND p.category_id = ? AND p.id <> ?
      ORDER BY p.stock = 'in-stock' DESC, p.price LIMIT 3",
    [$p['category_id'], $p['id']]
);

$name = setting('company_name');
$page_title = $p['name'] . ' — ' . $name;
$page_desc  = $p['name'] . ' (' . $p['sku'] . '), ' . $typeText . '. Fits ' . $p['fits'] . '.';
$nav = 'parts';
require __DIR__ . '/includes/header.php';
?>

  <section class="page-hero page-hero--slim">
    <div class="wrap">
      <p class="crumbs">
        <a href="<?= e(url('index.php')) ?>">Home</a> /
        <a href="<?= e(url('parts.php')) ?>">Spare parts</a> /
        <a href="<?= e(url('parts.php?category=' . urlencode($p['category_slug']))) ?>"><?= e($p['category_name']) ?></a>
      </p>
      <h1><?= e($p['name']) ?></h1>
      <p>SKU <?= e($p['sku']) ?> · <?= e($p['brand']) ?> · <?= e($typeText) ?></p>
    </div>
  </section>

  <section class="section">
    <div class="wrap">
      <div class="detail-grid">
        <div>
          <div class="gallery">
            <div class="gallery-main">
              <img id="gallery-main-img"
                   src="<?= e(photo_url($photos[0]['filename'] ?? null, 'assets/img/parts/' . $p['category_slug'] . '.svg')) ?>"
                   alt="<?= e($p['name']) ?>" width="800" height="500">
              <span class="card-flag <?= $inStock ? 'card-flag--stock' : 'card-flag--order' ?>">
                <?= $inStock ? 'In stock' : 'On order' ?></span>
            </div>
            <?php if (count($photos) > 1): ?>
              <div class="gallery-strip">
                <?php foreach ($photos as $i => $ph): ?>
                  <button type="button" class="gallery-thumb<?= $i === 0 ? ' is-active' : '' ?>"
                          data-full="<?= e(photo_url($ph['filename'], 'assets/img/parts/' . $p['category_slug'] . '.svg')) ?>">
                    <img src="<?= e(photo_url($ph['filename'], 'assets/img/parts/' . $p['category_slug'] . '.svg')) ?>"
                         alt="View <?= $i + 1 ?>" loading="lazy">
                  </button>
                <?php endforeach; ?>
              </div>
            <?php endif; ?>
          </div>

          <div class="panel" style="margin-top:22px">
            <h3>Details</h3>
            <div class="table-scroll" style="margin-top:12px">
              <table>
                <tbody>
                  <tr><th>Reference</th><td><?= e($p['ref']) ?></td></tr>
                  <tr><th>Part number</th><td><?= e($p['sku']) ?></td></tr>
                  <tr><th>Brand</th><td><?= e($p['brand']) ?></td></tr>
                  <tr><th>Category</th><td><?= e($p['category_name']) ?></td></tr>
                  <tr><th>Grade</th><td><?= e($typeText) ?></td></tr>
                  <tr><th>Size</th><td><?= e(size_label($p['size'])) ?></td></tr>
                  <tr><th>Fits</th><td><?= e($p['fits']) ?></td></tr>
                  <tr><th>Availability</th><td><?= $inStock ? 'In stock' : 'On order' ?></td></tr>
                </tbody>
              </table>
            </div>
            <?php if (!empty($p['note'])): ?>
              <p style="margin:16px 0 0"><?= e($p['note']) ?></p>
            <?php endif; ?>
          </div>
        </div>

        <aside>
          <div class="panel buy-panel">
            <span class="price price--lg"><?= e(money($p['price'])) ?><small>ex-works, per unit</small></span>
            <div class="btn-row" style="margin-top:18px">
              <a class="btn btn--primary btn--block"
                 href="<?= e(url('contact.php?ref=' . urlencode($p['ref']))) ?>">Order or ask a question</a>
            </div>
            <div class="btn-row" style="margin-top:10px">
              <a class="btn btn--ghost btn--block" target="_blank" rel="noopener"
                 href="<?= e(wa_link('Hello ' . $name . ', I need a quote for ' . $p['name'] . ' (SKU ' . $p['sku'] . ').')) ?>">
                 Ask on WhatsApp</a>
            </div>
            <ul class="contact-mini">
              <li>📞 <a href="tel:<?= e(preg_replace('/\s+/', '', setting('phone'))) ?>"><?= e(setting('phone')) ?></a></li>
              <li>✉ <a href="mailto:<?= e(setting('parts_email')) ?>"><?= e(setting('parts_email')) ?></a></li>
            </ul>
          </div>

          <div class="note" style="margin-top:20px">
            <p>Send your chassis number with the order (e.g. <code>NZE141-1234567</code>) and we
               will confirm the part fits before anything is dispatched.</p>
          </div>
        </aside>
      </div>

      <?php if ($related): ?>
        <div class="section-head" style="margin-top:56px">
          <span class="eyebrow">Same category</span>
          <h2>Other <?= e(strtolower($p['category_name'])) ?></h2>
        </div>
        <div class="grid grid--3">
          <?php foreach ($related as $r) { part_card($r); } ?>
        </div>
      <?php endif; ?>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
