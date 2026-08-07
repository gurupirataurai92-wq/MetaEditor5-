<?php
/** Spare-parts catalogue, filtered in SQL. */
require __DIR__ . '/includes/bootstrap.php';
require __DIR__ . '/includes/cards.php';

$categories = q_all('SELECT * FROM part_categories ORDER BY sort_order');
$slugs = array_column($categories, 'slug');

$where  = ['p.is_published = 1'];
$params = [];

$q = trim((string)($_GET['q'] ?? ''));
if ($q !== '') {
    $where[] = '(p.name LIKE ? OR p.sku LIKE ? OR p.brand LIKE ? OR p.fits LIKE ? OR p.ref LIKE ?)';
    $like = '%' . $q . '%';
    array_push($params, $like, $like, $like, $like, $like);
}

$category = (string)($_GET['category'] ?? '');
if ($category !== '' && in_array($category, $slugs, true)) {
    $where[] = 'c.slug = ?'; $params[] = $category;
} else {
    $category = '';
}

$size = (string)($_GET['size'] ?? '');
if (in_array($size, ['small', 'medium', 'large'], true)) { $where[] = 'p.size = ?'; $params[] = $size; }

$type = (string)($_GET['type'] ?? '');
if (in_array($type, ['genuine', 'oem', 'aftermarket', 'used'], true)) { $where[] = 'p.type = ?'; $params[] = $type; }

$stock = (string)($_GET['stock'] ?? '');
if (in_array($stock, ['in-stock', 'order'], true)) { $where[] = 'p.stock = ?'; $params[] = $stock; }

$sorts = [
    ''           => 'p.stock = "in-stock" DESC, p.updated_at DESC',
    'price-asc'  => 'p.price ASC',
    'price-desc' => 'p.price DESC',
    'name'       => 'p.name ASC',
];
$sortKey = (string)($_GET['sort'] ?? '');
$orderBy = $sorts[$sortKey] ?? $sorts[''];

$sqlWhere = implode(' AND ', $where);
$from = 'FROM parts p JOIN part_categories c ON c.id = p.category_id WHERE ' . $sqlWhere;

$total = (int)q_val("SELECT COUNT(*) $from", $params);
$page  = max(1, (int)($_GET['page'] ?? 1));
$pages = max(1, (int)ceil($total / ITEMS_PER_PAGE));
$page  = min($page, $pages);
$offset = ($page - 1) * ITEMS_PER_PAGE;

$rows = q_all(
    "SELECT p.*, c.slug AS category_slug, c.name AS category_name,
            (SELECT ph.filename FROM photos ph
              WHERE ph.item_type='part' AND ph.item_id=p.id
              ORDER BY ph.sort_order, ph.id LIMIT 1) AS cover,
            (SELECT COUNT(*) FROM photos ph
              WHERE ph.item_type='part' AND ph.item_id=p.id) AS photo_count
     $from ORDER BY $orderBy LIMIT " . (int)ITEMS_PER_PAGE . " OFFSET " . (int)$offset,
    $params
);

$grandTotal = (int)q_val('SELECT COUNT(*) FROM parts WHERE is_published = 1');

$page_title = 'Spare parts catalogue — ' . setting('company_name');
$page_desc  = 'Genuine, OEM, aftermarket and Japan-used spare parts for Japanese vehicles — from '
            . 'clips, filters and sensors to gearboxes and complete engines.';
$nav = 'parts';
require __DIR__ . '/includes/header.php';
?>

  <section class="page-hero">
    <div class="wrap">
      <p class="crumbs"><a href="<?= e(url('index.php')) ?>">Home</a> / Spare parts</p>
      <h1>Spare parts — small to big</h1>
      <p>A clip, a sensor, a filter kit, a suspension arm, a gearbox, a complete engine. Genuine,
         OEM, quality aftermarket and Japan-used stock, matched to your chassis number so it fits
         the first time.</p>
    </div>
  </section>

  <section class="section">
    <div class="wrap">

      <form class="toolbar" method="get" action="<?= e(url('parts.php')) ?>">
        <input type="hidden" name="category" value="<?= e($category) ?>">
        <div class="field-row">
          <div class="field">
            <label for="p-q">Search parts</label>
            <input type="search" id="p-q" name="q" value="<?= e($q) ?>" placeholder="Part name, SKU, brand or vehicle…">
          </div>
          <div class="field">
            <label for="p-size">Part size</label>
            <select id="p-size" name="size">
              <option value="">Any size</option>
              <?php foreach (['small' => 'Small (clips, filters, sensors)',
                              'medium' => 'Medium (pumps, lamps, shocks)',
                              'large' => 'Large (engines, gearboxes, panels)'] as $k => $label): ?>
                <option value="<?= e($k) ?>"<?= $size === $k ? ' selected' : '' ?>><?= e($label) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="p-type">Part type</label>
            <select id="p-type" name="type">
              <option value="">Any type</option>
              <?php foreach (['genuine' => 'Genuine', 'oem' => 'OEM',
                              'aftermarket' => 'Aftermarket', 'used' => 'Japan used'] as $k => $label): ?>
                <option value="<?= e($k) ?>"<?= $type === $k ? ' selected' : '' ?>><?= e($label) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="p-stock">Availability</label>
            <select id="p-stock" name="stock">
              <option value="">Any</option>
              <option value="in-stock"<?= $stock === 'in-stock' ? ' selected' : '' ?>>In stock</option>
              <option value="order"<?= $stock === 'order' ? ' selected' : '' ?>>On order</option>
            </select>
          </div>
          <div class="field">
            <label for="p-sort">Sort by</label>
            <select id="p-sort" name="sort">
              <?php foreach (['' => 'Featured', 'price-asc' => 'Price: low to high',
                              'price-desc' => 'Price: high to low', 'name' => 'Name A–Z'] as $k => $label): ?>
                <option value="<?= e($k) ?>"<?= $sortKey === $k ? ' selected' : '' ?>><?= e($label) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
        </div>

        <div class="toolbar-foot">
          <div class="chips">
            <a class="chip" aria-pressed="<?= $category === '' ? 'true' : 'false' ?>"
               href="<?= e(with_query(['category' => null, 'page' => null])) ?>">All categories</a>
            <?php foreach ($categories as $c): ?>
              <a class="chip" aria-pressed="<?= $category === $c['slug'] ? 'true' : 'false' ?>"
                 href="<?= e(with_query(['category' => $c['slug'], 'page' => null])) ?>"><?= e($c['name']) ?></a>
            <?php endforeach; ?>
          </div>
          <div class="btn-row">
            <p class="result-count"><b><?= $total ?></b> of <?= $grandTotal ?> part lines shown</p>
            <button class="btn btn--primary btn--sm" type="submit">Apply filters</button>
            <a class="btn btn--ghost btn--sm" href="<?= e(url('parts.php')) ?>">Reset</a>
          </div>
        </div>
      </form>

      <div class="grid grid--3">
        <?php foreach ($rows as $p) { part_card($p); } ?>
        <?php if (!$rows): ?>
          <div class="empty">
            <h3>Nothing matches those filters</h3>
            <p>Try widening your search — or ask us to source the part for you.</p>
            <a class="btn btn--ghost btn--sm" href="<?= e(url('contact.php')) ?>">Request a sourcing quote</a>
          </div>
        <?php endif; ?>
      </div>

      <?php pager($total, $page, ITEMS_PER_PAGE); ?>
    </div>
  </section>

  <section class="section section--dark">
    <div class="wrap">
      <div class="grid grid--2 grid--top">
        <div>
          <span class="eyebrow">Sourcing service</span>
          <h2>If it is not on the shelf, we will find it</h2>
          <p style="color:var(--text-invert-soft)">
            The catalogue above is our fast-moving stock — a fraction of what we supply. Our buyers
            work with dismantlers in Japan, OEM distributors and Dubai wholesalers every day.
          </p>
          <div class="steps" style="margin-top:22px">
            <div class="step"><h3>Send the chassis number</h3>
              <p>The plate under the bonnet or on the door pillar, e.g. <code>NZE141-1234567</code>.</p></div>
            <div class="step"><h3>We match the catalogue</h3>
              <p>We confirm the exact part number against the manufacturer catalogue before quoting.</p></div>
            <div class="step"><h3>Quote within 48 hours</h3>
              <p>Genuine, OEM and aftermarket options side by side, with prices and lead times.</p></div>
          </div>
          <div class="btn-row" style="margin-top:22px">
            <a class="btn btn--accent" href="<?= e(url('contact.php?ref=a spare part')) ?>">Request a part quote</a>
          </div>
        </div>

        <div>
          <div class="panel panel--dark">
            <h3>Grades of part we supply</h3>
            <div class="table-scroll" style="margin-top:14px">
              <table>
                <thead><tr><th>Grade</th><th>Best for</th></tr></thead>
                <tbody>
                  <tr><td><b>Genuine</b></td><td>Dealer-boxed parts. Safety-critical items and anything under warranty.</td></tr>
                  <tr><td><b>OEM</b></td><td>Same factory, supplier's own box — Denso, Aisin, KYB, Exedy.</td></tr>
                  <tr><td><b>Aftermarket</b></td><td>Quality-brand equivalents for older vehicles and cost-sensitive repairs.</td></tr>
                  <tr><td><b>Japan used</b></td><td>Low-mileage removals — engines, gearboxes, lamps, panels.</td></tr>
                </tbody>
              </table>
            </div>
            <p style="margin-top:16px;font-size:.88rem">
              Engines, gearboxes and differentials carry a three-month exchange warranty against
              internal failure. Electrical items are tested but sold as-is unless stated otherwise.
            </p>
          </div>
        </div>
      </div>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
