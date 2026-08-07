<?php
/**
 * Vehicle catalogue.
 *
 * Filtering happens in SQL. Every value the visitor supplies is bound as a
 * parameter; the only things interpolated into the statement are column names
 * chosen from fixed lists in this file.
 */
require __DIR__ . '/includes/bootstrap.php';
require __DIR__ . '/includes/cards.php';

$where  = ['v.is_published = 1'];
$params = [];

$q = trim((string)($_GET['q'] ?? ''));
if ($q !== '') {
    $where[] = '(v.make LIKE ? OR v.model LIKE ? OR v.colour LIKE ? OR v.ref LIKE ? OR v.note LIKE ?)';
    $like = '%' . $q . '%';
    array_push($params, $like, $like, $like, $like, $like);
}

$make = trim((string)($_GET['make'] ?? ''));
if ($make !== '') { $where[] = 'v.make = ?'; $params[] = $make; }

$body = (string)($_GET['body'] ?? '');
if (in_array($body, ['sedan', 'hatchback', 'suv', 'van', 'pickup', 'truck'], true)) {
    $where[] = 'v.body = ?'; $params[] = $body;
}

$fuel = (string)($_GET['fuel'] ?? '');
if (in_array($fuel, ['Petrol', 'Diesel', 'Hybrid', 'Electric'], true)) {
    $where[] = 'v.fuel = ?'; $params[] = $fuel;
}

$gear = (string)($_GET['transmission'] ?? '');
if (in_array($gear, ['Automatic', 'Manual'], true)) {
    $where[] = 'v.transmission = ?'; $params[] = $gear;
}

$status = (string)($_GET['status'] ?? '');
if (in_array($status, ['in-stock', 'in-transit', 'to-order'], true)) {
    $where[] = 'v.status = ?'; $params[] = $status;
}

$budget = (int)($_GET['budget'] ?? 0);
if ($budget > 0) { $where[] = 'v.price <= ?'; $params[] = $budget; }

/* Sorting: the key picks a fixed expression, never the visitor's own text. */
$sorts = [
    ''            => 'v.status = "in-stock" DESC, v.updated_at DESC',
    'price-asc'   => 'v.price ASC',
    'price-desc'  => 'v.price DESC',
    'year-desc'   => 'v.year DESC',
    'mileage-asc' => 'v.mileage ASC',
];
$sortKey = (string)($_GET['sort'] ?? '');
$orderBy = $sorts[$sortKey] ?? $sorts[''];

$sqlWhere = implode(' AND ', $where);
$total = (int)q_val("SELECT COUNT(*) FROM vehicles v WHERE $sqlWhere", $params);

$page   = max(1, (int)($_GET['page'] ?? 1));
$pages  = max(1, (int)ceil($total / ITEMS_PER_PAGE));
$page   = min($page, $pages);
$offset = ($page - 1) * ITEMS_PER_PAGE;

$rows = q_all(
    "SELECT v.*,
            (SELECT p.filename FROM photos p
              WHERE p.item_type='vehicle' AND p.item_id=v.id
              ORDER BY p.sort_order, p.id LIMIT 1) AS cover,
            (SELECT COUNT(*) FROM photos p
              WHERE p.item_type='vehicle' AND p.item_id=v.id) AS photo_count
       FROM vehicles v
      WHERE $sqlWhere
      ORDER BY $orderBy
      LIMIT " . (int)ITEMS_PER_PAGE . " OFFSET " . (int)$offset,
    $params
);

$grandTotal = (int)q_val('SELECT COUNT(*) FROM vehicles WHERE is_published = 1');
$makes = q_all('SELECT DISTINCT make FROM vehicles WHERE is_published = 1 ORDER BY make');

$page_title = 'Imported vehicles in stock — ' . setting('company_name');
$page_desc  = 'Browse imported Japanese cars, SUVs, vans, pickups and trucks. Filter by make, body '
            . 'type, fuel, gearbox and budget.';
$nav = 'vehicles';
require __DIR__ . '/includes/header.php';
?>

  <section class="page-hero">
    <div class="wrap">
      <p class="crumbs"><a href="<?= e(url('index.php')) ?>">Home</a> / Vehicles</p>
      <h1>Imported vehicles</h1>
      <p>Units in our yard, on the water, or available to order from the next Japanese auction.
         Prices shown are CIF to your nearest port and exclude import duty and local taxes.</p>
    </div>
  </section>

  <section class="section">
    <div class="wrap">

      <form class="toolbar" method="get" action="<?= e(url('vehicles.php')) ?>">
        <div class="field-row">
          <div class="field">
            <label for="f-q">Search</label>
            <input type="search" id="f-q" name="q" value="<?= e($q) ?>" placeholder="Model, colour, reference…">
          </div>
          <div class="field">
            <label for="f-make">Make</label>
            <select id="f-make" name="make">
              <option value="">Any make</option>
              <?php foreach ($makes as $m): ?>
                <option value="<?= e($m['make']) ?>"<?= $make === $m['make'] ? ' selected' : '' ?>><?= e($m['make']) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="f-body">Body type</label>
            <select id="f-body" name="body">
              <option value="">Any body</option>
              <?php foreach (['sedan' => 'Sedan', 'hatchback' => 'Hatchback', 'suv' => 'SUV / 4WD',
                              'van' => 'Van / MPV', 'pickup' => 'Pickup', 'truck' => 'Truck'] as $k => $label): ?>
                <option value="<?= e($k) ?>"<?= $body === $k ? ' selected' : '' ?>><?= e($label) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="f-fuel">Fuel</label>
            <select id="f-fuel" name="fuel">
              <option value="">Any fuel</option>
              <?php foreach (['Petrol', 'Diesel', 'Hybrid', 'Electric'] as $f): ?>
                <option<?= $fuel === $f ? ' selected' : '' ?>><?= e($f) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="f-gear">Gearbox</label>
            <select id="f-gear" name="transmission">
              <option value="">Any gearbox</option>
              <?php foreach (['Automatic', 'Manual'] as $g): ?>
                <option<?= $gear === $g ? ' selected' : '' ?>><?= e($g) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="f-budget">Budget up to (USD)</label>
            <select id="f-budget" name="budget">
              <option value="">No limit</option>
              <?php foreach ([8000, 15000, 25000, 40000] as $b): ?>
                <option value="<?= $b ?>"<?= $budget === $b ? ' selected' : '' ?>>$<?= number_format($b) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
          <div class="field">
            <label for="f-sort">Sort by</label>
            <select id="f-sort" name="sort">
              <?php foreach (['' => 'Featured', 'price-asc' => 'Price: low to high',
                              'price-desc' => 'Price: high to low', 'year-desc' => 'Newest year',
                              'mileage-asc' => 'Lowest mileage'] as $k => $label): ?>
                <option value="<?= e($k) ?>"<?= $sortKey === $k ? ' selected' : '' ?>><?= e($label) ?></option>
              <?php endforeach; ?>
            </select>
          </div>
        </div>

        <div class="toolbar-foot">
          <div class="chips">
            <?php foreach (['' => 'All units', 'in-stock' => 'In stock',
                            'in-transit' => 'In transit', 'to-order' => 'To order'] as $k => $label): ?>
              <a class="chip" aria-pressed="<?= $status === $k ? 'true' : 'false' ?>"
                 href="<?= e(with_query(['status' => $k, 'page' => null])) ?>"><?= e($label) ?></a>
            <?php endforeach; ?>
          </div>
          <div class="btn-row">
            <p class="result-count"><b><?= $total ?></b> of <?= $grandTotal ?> vehicles shown</p>
            <button class="btn btn--primary btn--sm" type="submit">Apply filters</button>
            <a class="btn btn--ghost btn--sm" href="<?= e(url('vehicles.php')) ?>">Reset</a>
          </div>
        </div>
      </form>

      <div class="grid grid--3">
        <?php foreach ($rows as $v) { vehicle_card($v); } ?>
        <?php if (!$rows): ?>
          <div class="empty">
            <h3>Nothing matches those filters</h3>
            <p>Try widening your search — or ask us to source the vehicle for you.</p>
            <a class="btn btn--ghost btn--sm" href="<?= e(url('contact.php')) ?>">Request a sourcing quote</a>
          </div>
        <?php endif; ?>
      </div>

      <?php pager($total, $page, ITEMS_PER_PAGE); ?>

      <div class="note" style="margin-top:28px">
        <p><b>Not listed?</b> Roughly half of what we deliver never appears on this page — it is bid
           for to order. Tell us the model, year range, maximum mileage and budget and we will send
           you matching auction sheets as they come up.
           <a href="<?= e(url('contact.php')) ?>">Send a sourcing brief →</a></p>
      </div>
    </div>
  </section>

<?php require __DIR__ . '/includes/footer.php'; ?>
